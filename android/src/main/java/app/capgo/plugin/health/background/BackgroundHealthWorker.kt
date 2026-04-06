package app.capgo.plugin.health.background

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class BackgroundHealthWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val logger = BackgroundHealthDebugLogger.create(applicationContext)
        logger.append("Worker doWork started runId=$id runAttemptCount=$runAttemptCount")
        val coordinator = BackgroundHealthCoordinator(applicationContext, debugLogger = logger)
        val result = coordinator.run()
        logger.append("Worker doWork finished result=${result.javaClass.simpleName}")
        return result
    }
}
