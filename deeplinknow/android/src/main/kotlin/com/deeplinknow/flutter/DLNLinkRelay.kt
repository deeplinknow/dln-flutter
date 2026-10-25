package com.deeplinknow.flutter

import android.content.Intent

/**
 * Buffers the URLs the OS opens the app with until Dart asks for them (SDK-87), then forwards
 * each new one. Nothing here parses or decides: Dart applies the native parse rules (FLT-01).
 *
 * - [offer]: a URL from the launch intent or `onNewIntent`. Buffered until [start], pushed after.
 * - [start]: Dart's `startLinks` call. Returns the buffer (launch URL first) and starts pushing.
 * - A push that Dart doesn't answer (no handler after a hot restart) goes back into the buffer
 *   and pushing stops until the next [start], so no URL is lost.
 *
 * Main thread only (the activity callbacks and the channel both run there).
 */
internal class DLNLinkRelay(
    private val push: (url: String, delivered: (Boolean) -> Unit) -> Unit,
) {
    private val pending = ArrayDeque<String>()
    private var dartListening = false

    fun offer(url: String) {
        if (!dartListening) {
            pending.addLast(url)
            return
        }
        push(url) { delivered ->
            if (!delivered) {
                pending.addLast(url)
                dartListening = false
            }
        }
    }

    fun start(): List<String> {
        dartListening = true
        val urls = pending.toList()
        pending.clear()
        return urls
    }

    /** The engine detached: buffer again until Dart calls `startLinks`. */
    fun stop() {
        dartListening = false
    }

    companion object {
        /** `Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`: reopened from Recents, not a new open. */
        const val FLAG_LAUNCHED_FROM_HISTORY = 0x00100000

        /**
         * The URL of an intent that opens a link: an `ACTION_VIEW` with data, not relaunched from
         * Recents (which replays the original intent, SDK-88). `null` otherwise.
         */
        fun urlOf(action: String?, data: String?, flags: Int): String? =
            if (action == Intent.ACTION_VIEW && !data.isNullOrEmpty() && (flags and FLAG_LAUNCHED_FROM_HISTORY) == 0) data else null
    }
}
