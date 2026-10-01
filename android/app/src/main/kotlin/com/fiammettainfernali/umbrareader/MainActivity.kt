package com.fiammettainfernali.umbrareader

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    private companion object {
        const val DEFINE_CHANNEL = "umbra/define"
        const val OPEN_IN_CHANNEL = "umbra/open_in"
    }
}
