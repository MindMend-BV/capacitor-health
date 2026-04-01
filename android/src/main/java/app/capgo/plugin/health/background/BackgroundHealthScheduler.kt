package app.capgo.plugin.health.background

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkInfo
import java.util.concurrent.TimeUnit

class BackgroundHealthScheduler(private val context: Context) {
    fun schedule(config: BackgroundSyncConfig) {
        val intervalMinutes = config.intervalMinutes.coerceAtLeast(MIN_INTERVAL_MINUTES)
        val request = PeriodicWorkRequestBuilder<BackgroundHealthWorker>(
            intervalMinutes,
            TimeUnit.MINUTES
        )
            .setConstraints(defaultConstraints())
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            UNIQUE_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }

    fun cancel() {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
    }

    fun isScheduled(): Boolean {
        val workInfos = WorkManager.getInstance(context).getWorkInfosForUniqueWork(UNIQUE_WORK_NAME).get()
        return workInfos.any { workInfo ->
            workInfo.state == WorkInfo.State.ENQUEUED ||
                workInfo.state == WorkInfo.State.RUNNING ||
                workInfo.state == WorkInfo.State.BLOCKED
        }
    }

    private fun defaultConstraints(): Constraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()

    companion object {
        const val UNIQUE_WORK_NAME = "capgo.health.background.sync"
        const val MIN_INTERVAL_MINUTES = 15L
    }
}
