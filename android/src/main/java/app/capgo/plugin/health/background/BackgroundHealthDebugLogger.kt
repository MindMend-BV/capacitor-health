package app.capgo.plugin.health.background

import android.content.Context
import android.content.pm.ApplicationInfo
import java.io.File
import java.io.FileWriter
import java.io.IOException
import java.time.Instant

/**
 * Append-only debug log on the device at [LOG_FILE_NAME] under the app [Context.getFilesDir].
 * Only writes when the app is debuggable ([ApplicationInfo.FLAG_DEBUGGABLE]); no-op in release.
 *
 * Path pattern: `/data/data/<package>/files/background_health_worker_debug.log`
 *
 * Pull with a debuggable build: `adb shell run-as <package> cat files/background_health_worker_debug.log`
 */
class BackgroundHealthDebugLogger private constructor(
    private val appContext: Context,
    private val enabled: Boolean
) {
    private val logFile = File(appContext.filesDir, LOG_FILE_NAME)

    fun append(message: String) {
        if (!enabled) {
            return
        }
        val line = "${Instant.now()} | $message\n"
        synchronized(lock) {
            try {
                FileWriter(logFile, true).use { it.append(line) }
                trimIfTooLarge()
            } catch (_: IOException) {
                // Best-effort only.
            }
        }
    }

    private fun trimIfTooLarge() {
        if (!logFile.exists() || logFile.length() <= MAX_BYTES) {
            return
        }
        try {
            logFile.delete()
            FileWriter(logFile, true).use { writer ->
                writer.append("${Instant.now()} | --- log cleared: exceeded ${MAX_BYTES}B ---\n")
            }
        } catch (_: IOException) {
        }
    }

    companion object {
        const val LOG_FILE_NAME = "background_health_worker_debug.log"
        private const val MAX_BYTES = 512_000L
        private val lock = Any()

        fun create(context: Context): BackgroundHealthDebugLogger {
            val app = context.applicationContext
            val debuggable = (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            return BackgroundHealthDebugLogger(app, debuggable)
        }
    }
}
