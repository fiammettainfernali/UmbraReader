package com.fiammettainfernali.umbrareader

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.FileProvider
import androidx.webkit.ProfileStore
import androidx.webkit.ScriptHandler
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.io.File

/**
 * Android side of the `umbra/define` bridge.
 *
 * iOS answers a word lookup with UIReferenceLibraryViewController. Android has
 * no system dictionary UI at all, so the closest honest equivalent is to hand
 * the word to whatever dictionary or translator the reader has installed, via
 * PROCESS_TEXT. Where nothing handles it, the channel reports false and the
 * reader says so rather than swallowing the gesture.
 */
class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null

    /** A share that arrived before the Flutter side was ready to hear about it. */
    private var waitingShare: Map<String, String?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        takeShare(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val share = takeShare(intent) ?: return
        val channel = shareChannel ?: return
        waitingShare = null
        channel.invokeMethod("shared", share)
    }

    /**
     * Holds on to a share and takes it off the intent, so it only counts once.
     *
     * Android hands an activity its original intent again when it's recreated or
     * reopened from Recents, and a link sent twice would ask about a duplicate
     * nobody made.
     */
    private fun takeShare(intent: Intent?): Map<String, String?>? {
        if (intent?.action != ACTION_SHARED) return null
        val reopened = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.removeExtra(Intent.EXTRA_SUBJECT)
        if (reopened || text == null) return null
        return mapOf("text" to text, "subject" to subject).also { waitingShare = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "takeWaiting" -> {
                            result.success(waitingShare)
                            waitingShare = null
                        }
                        // Back to whatever was on screen before the share.
                        "leave" -> result.success(moveTaskToBack(true))
                        else -> result.notImplemented()
                    }
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEFINE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "define") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val term = call.argument<String>("term")
                if (term.isNullOrBlank()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                result.success(define(term))
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OPEN_IN_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val mimeType = call.argument<String>("mimeType")
                if (path.isNullOrBlank() || mimeType.isNullOrBlank()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                result.success(openIn(path, mimeType))
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BROWSER_CHANNEL)
            .setMethodCallHandler { call, result ->
                val viewId = call.argument<Number>("viewId")?.toLong()
                when (call.method) {
                    "setProfile" -> result.success(
                        setProfile(flutterEngine, viewId, call.argument("profile")),
                    )
                    "setStartScript" -> result.success(
                        setStartScript(flutterEngine, viewId, call.argument("script")),
                    )
                    "forget" -> {
                        if (viewId != null) startScripts.remove(viewId)?.remove()
                        result.success(true)
                    }
                    "openExternally" -> result.success(openExternally(call.argument("url")))
                    else -> result.notImplemented()
                }
            }
    }

    /** One per browser tab, so the ad blocker can be switched off again. */
    private val startScripts = mutableMapOf<Long, ScriptHandler>()

    /**
     * Gives a web view its own cookies and site data.
     *
     * Android normally shares those across every web view in an app, which is
     * what would let a sign-in in one browser leak into the other. Reports
     * false rather than failing where the phone's WebView is too old for this:
     * the browser still works, just with shared sign-ins.
     */
    private fun setProfile(engine: FlutterEngine, viewId: Long?, profile: String?): Boolean {
        if (viewId == null || profile.isNullOrBlank()) return false
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return false
        val view = WebViewFlutterAndroidExternalApi.getWebView(engine, viewId) ?: return false
        return try {
            ProfileStore.getInstance().getOrCreateProfile(profile)
            WebViewCompat.setProfile(view, profile)
            true
        } catch (e: IllegalStateException) {
            // The web view has already been used, so it keeps the shared data.
            false
        }
    }

    /**
     * Runs [script] before a page's own scripts, on every page from now on.
     * Null takes it off again. Running first is the point: by the time a page
     * has finished loading, its pop-up scripts have already had their chance.
     */
    private fun setStartScript(engine: FlutterEngine, viewId: Long?, script: String?): Boolean {
        if (viewId == null) return false
        startScripts.remove(viewId)?.remove()
        if (script == null) return true
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return false
        val view = WebViewFlutterAndroidExternalApi.getWebView(engine, viewId) ?: return false
        startScripts[viewId] = WebViewCompat.addDocumentStartJavaScript(view, script, setOf("*"))
        return true
    }

    /** Hands a web address to the phone's own browser. */
    private fun openExternally(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /**
     * Hands a file to whatever app can open it.
     *
     * Not a share. The two are different sets: a read-aloud app may register
     * EPUB under VIEW while accepting only plain text under SEND, in which
     * case it is missing from the share sheet while being the only app on the
     * phone that can read the book. Sharing the file offered the reader
     * Bluetooth and Gmail; this offers them the app they actually wanted.
     */
    private fun openIn(path: String, mimeType: String): Boolean {
        val file = File(path)
        if (!file.isFile) return false

        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.files", file)
        } catch (e: IllegalArgumentException) {
            // The file is outside the paths the provider is allowed to share,
            // which is a wiring mistake rather than anything the reader did.
            return false
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            // Without this the receiving app gets a URI it is not allowed to
            // read, and fails after being chosen — which looks like the book
            // being broken rather than the handover.
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // Same lesson as `define`: an empty chooser is worse than an honest
        // no, and this needs the matching <queries> element to see anything
        // on API 30+.
        if (packageManager.queryIntentActivities(intent, 0).isEmpty()) {
            return false
        }

        return try {
            startActivity(Intent.createChooser(intent, "Open with"))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun define(term: String): Boolean {
        val intent = Intent(Intent.ACTION_PROCESS_TEXT).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_PROCESS_TEXT, term)
            // Read-only: the reader is looking a word up, not editing it, so
            // handlers should not offer to send a replacement back.
            putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
        }

        // An empty chooser is worse than an honest no. This needs the
        // <queries> element in the manifest: without it the query comes back
        // empty on API 30+ however many dictionaries are installed.
        if (packageManager.queryIntentActivities(intent, 0).isEmpty()) {
            return false
        }

        return try {
            startActivity(Intent.createChooser(intent, "Define"))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    companion object {
        /** How [ShareTargetActivity] says this intent is carrying a share. */
        const val ACTION_SHARED = "com.fiammettainfernali.umbrareader.SHARED"

        private const val DEFINE_CHANNEL = "umbra/define"
        private const val OPEN_IN_CHANNEL = "umbra/open_in"
        private const val BROWSER_CHANNEL = "umbra/browser"
        private const val SHARE_CHANNEL = "umbra/share"
    }
}
