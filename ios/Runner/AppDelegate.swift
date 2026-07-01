import Flutter
import UIKit
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nowPlaying: NowPlayingBridge?
  private var iCloudKv: ICloudKvBridge?

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
