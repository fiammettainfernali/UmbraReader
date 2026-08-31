package com.fiammettainfernali.umbrareader

import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }
}
