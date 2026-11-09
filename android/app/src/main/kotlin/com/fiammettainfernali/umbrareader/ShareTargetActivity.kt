package com.fiammettainfernali.umbrareader

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * What Android's share menu opens. It only passes the link along to the app.
 *
 * Android starts a share target inside the task of the app that shared, so
 * without this a share could start a second copy of the whole app alongside the
 * one already open, each with the same database. This has no screen and goes
 * away at once, and the real app comes forward as itself.
 */
class ShareTargetActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val shared = intent
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                action = MainActivity.ACTION_SHARED
                putExtra(Intent.EXTRA_TEXT, shared?.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString())
                putExtra(Intent.EXTRA_SUBJECT, shared?.getStringExtra(Intent.EXTRA_SUBJECT))
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
        )
        finish()
    }
}
