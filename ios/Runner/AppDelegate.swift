import Flutter
import UIKit
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nowPlaying: NowPlayingBridge?
  private var iCloudKv: ICloudKvBridge?
  private var iCloudDocs: ICloudDocsBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NowPlayingBridge") {
      nowPlaying = NowPlayingBridge(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudKvBridge") {
      iCloudKv = ICloudKvBridge(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudDocsBridge") {
      iCloudDocs = ICloudDocsBridge(messenger: registrar.messenger())
    }
  }
}

/// Bridges Dart to JSON files in the app's private iCloud Drive container
/// (the "Documents" ubiquity directory) — the successor to the key-value
/// store bridge below, without its 1 MB total-size limit.
///
/// Dart calls `read` / `write` / `available`. A metadata query watches the
/// container and forwards remote changes to Dart as `changedExternally` so a
/// running app can merge edits from the user's other devices live. All file
/// I/O runs off the main thread and goes through NSFileCoordinator so it
/// cooperates with the iCloud daemon's own reads and writes.
final class ICloudDocsBridge: NSObject {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "umbra.icloud.docs", qos: .utility)
  private var cachedDocsUrl: URL?
  private var query: NSMetadataQuery?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "umbra/icloud_docs",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    startWatching()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "read":
      guard let name = args?["name"] as? String else { result(nil); return }
      queue.async { [weak self] in
        let value = self?.readFile(name)
        DispatchQueue.main.async { result(value) }
      }
    case "write":
      guard let name = args?["name"] as? String,
            let value = args?["value"] as? String else { result(false); return }
      queue.async { [weak self] in
        let ok = self?.writeFile(name, value) ?? false
        DispatchQueue.main.async { result(ok) }
      }
    case "available":
      queue.async { [weak self] in
        let ok = self?.documentsUrl() != nil
        DispatchQueue.main.async { result(ok) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The container's Documents directory, or nil when iCloud is unavailable
  /// (signed out, iCloud Drive off, no entitlement). Resolved lazily and
  /// cached — `url(forUbiquityContainerIdentifier:)` can block, which is why
  /// everything runs on [queue].
  private func documentsUrl() -> URL? {
    if let cached = cachedDocsUrl { return cached }
    guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil)
    else { return nil }
    let docs = base.appendingPathComponent("Documents", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: docs, withIntermediateDirectories: true)
    cachedDocsUrl = docs
    return docs
  }

  private func readFile(_ name: String) -> String? {
    guard let dir = documentsUrl() else { return nil }
    let url = dir.appendingPathComponent(name)
    let fm = FileManager.default
    if !fm.fileExists(atPath: url.path) {
      // Possibly a cloud item that hasn't been downloaded to this device yet
      // — request it and give the daemon a moment.
      try? fm.startDownloadingUbiquitousItem(at: url)
      for _ in 0..<20 {
        if fm.fileExists(atPath: url.path) { break }
        Thread.sleep(forTimeInterval: 0.1)
      }
      if !fm.fileExists(atPath: url.path) { return nil }
    }
    var out: String?
    let coordinator = NSFileCoordinator()
    var error: NSError?
    coordinator.coordinate(readingItemAt: url, options: [], error: &error) { u in
      out = try? String(contentsOf: u, encoding: .utf8)
    }
    return out
  }

  private func writeFile(_ name: String, _ value: String) -> Bool {
    guard let dir = documentsUrl() else { return false }
    let url = dir.appendingPathComponent(name)
    var ok = false
    let coordinator = NSFileCoordinator()
    var error: NSError?
    coordinator.coordinate(
      writingItemAt: url, options: .forReplacing, error: &error
    ) { u in
      ok = (try? value.write(to: u, atomically: true, encoding: .utf8)) != nil
    }
    return ok
  }

  /// Watches the container for versions arriving from other devices. New
  /// items are nudged to download so the next `read` sees them, and Dart is
  /// told to pull + merge.
  private func startWatching() {
    let q = NSMetadataQuery()
    q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
    q.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(queryUpdated(_:)),
      name: .NSMetadataQueryDidUpdate,
      object: q
    )
    query = q
    DispatchQueue.main.async {
      q.start()
      q.enableUpdates()
    }
  }

  @objc private func queryUpdated(_ note: Notification) {
    if let q = query {
      q.disableUpdates()
      for case let item as NSMetadataItem in q.results {
        if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
          try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
      }
      q.enableUpdates()
    }
    channel.invokeMethod("changedExternally", arguments: nil)
  }
}

/// Bridges Dart to iCloud key-value storage (`NSUbiquitousKeyValueStore`).
///
/// Dart calls `get` / `set` / `remove` / `getAll` / `synchronize` to read and
/// write small JSON blobs that iCloud mirrors across the user's devices. When
/// another device changes a value, the system posts
/// `didChangeExternallyNotification`; we forward the affected keys to Dart as a
/// `changedExternally` invocation so the running app can merge them live.
final class ICloudKvBridge {
  private let channel: FlutterMethodChannel
  private let store = NSUbiquitousKeyValueStore.default

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "umbra/icloud_kv",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(storeDidChangeExternally(_:)),
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: store
    )
    // Pull the latest cloud values into the local KVS cache at startup.
    store.synchronize()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "get":
      guard let key = args?["key"] as? String else { result(nil); return }
      result(store.string(forKey: key))
    case "set":
      if let key = args?["key"] as? String, let value = args?["value"] as? String {
        store.set(value, forKey: key)
        store.synchronize()
      }
      result(nil)
    case "remove":
      if let key = args?["key"] as? String {
        store.removeObject(forKey: key)
        store.synchronize()
      }
      result(nil)
    case "getAll":
      // Only string values are used by this app; filter the rest out.
      var out: [String: String] = [:]
      for (k, v) in store.dictionaryRepresentation {
        if let s = v as? String { out[k] = s }
      }
      result(out)
    case "synchronize":
      result(store.synchronize())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func storeDidChangeExternally(_ note: Notification) {
    let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
    channel.invokeMethod("changedExternally", arguments: keys)
  }
}

/// Bridges read-aloud playback to the iOS lock screen and Control Center.
///
/// `update`/`clear` calls from Dart publish Now Playing metadata; the system's
/// remote transport buttons are forwarded back to Dart as `play`, `pause`,
/// `toggle`, `next` and `previous` method invocations.
final class NowPlayingBridge {
  private let channel: FlutterMethodChannel
  private var commandsRegistered = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "umbra/now_playing",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      if let args = call.arguments as? [String: Any] {
        update(args)
      }
      result(nil)
    case "clear":
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func update(_ args: [String: Any]) {
    registerCommands()
    let title = args["title"] as? String ?? ""
    let book = args["book"] as? String ?? ""
    let isPlaying = args["isPlaying"] as? Bool ?? false

    var info: [String: Any] = [:]
    info[MPMediaItemPropertyTitle] = title
    info[MPMediaItemPropertyArtist] = book
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    // Cover artwork from a local file path, when available.
    if let path = args["artwork"] as? String,
       let image = UIImage(contentsOfFile: path) {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size
      ) { _ in image }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  /// Wires up the remote command handlers once, on first use.
  private func registerCommands() {
    if commandsRegistered { return }
    commandsRegistered = true
    let center = MPRemoteCommandCenter.shared()

    center.playCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("play", arguments: nil)
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("pause", arguments: nil)
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("toggle", arguments: nil)
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("next", arguments: nil)
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("previous", arguments: nil)
      return .success
    }

    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.nextTrackCommand.isEnabled = true
    center.previousTrackCommand.isEnabled = true
  }
}
