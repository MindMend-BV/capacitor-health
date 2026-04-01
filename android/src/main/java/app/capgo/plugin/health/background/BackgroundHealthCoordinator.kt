package app.capgo.plugin.health.background

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.work.ListenableWorker
import app.capgo.plugin.health.HealthDataType
import app.capgo.plugin.health.HealthManager
import com.getcapacitor.JSArray
import java.time.Duration
import java.time.Instant

class BackgroundHealthCoordinator(
    private val context: Context,
    private val preferences: BackgroundHealthPreferences = BackgroundHealthPreferences(context),
    private val healthManager: HealthManager = HealthManager(),
    private val permissionChecker: BackgroundHealthPermissionChecker =
        BackgroundHealthPermissionChecker(context, healthManager),
    private val apiClient: BackgroundHealthApiClient = BackgroundHealthApiClient()
) {
    suspend fun run(): ListenableWorker.Result {
        val config = preferences.getConfig() ?: return ListenableWorker.Result.success()
        if (!config.enabled) {
            return ListenableWorker.Result.success()
        }

        val status = HealthConnectClient.getSdkStatus(context)
        if (status != HealthConnectClient.SDK_AVAILABLE) {
            return ListenableWorker.Result.retry()
        }

        val client = HealthConnectClient.getOrCreate(context)
        if (!permissionChecker.hasRequiredPermissions(client, config)) {
            return ListenableWorker.Result.retry()
        }

        val lastSyncMap = try {
            apiClient.fetchLastSyncMap(config.getLastSync)
        } catch (error: Exception) {
            Log.w(TAG, "Background sync failed fetching last-sync state.", error)
            return ListenableWorker.Result.retry()
        }

        val endTime = Instant.now()
        val uploadedSamples = JSArray()
        var successfulReadCount = 0

        config.dataTypes.forEach { dataType ->
            try {
                val startTime = resolveStartTime(lastSyncMap, dataType, config, endTime)
                val samples = healthManager.readSamples(
                    client = client,
                    dataType = dataType,
                    startTime = startTime,
                    endTime = endTime,
                    limit = 0,
                    ascending = true
                )
                for (index in 0 until samples.length()) {
                    uploadedSamples.put(samples.opt(index))
                }
                successfulReadCount += 1
            } catch (error: Exception) {
                Log.w(TAG, "Background sync read failed for ${dataType.identifier}. Continuing with partial upload.", error)
            }
        }

        if (successfulReadCount == 0) {
            return ListenableWorker.Result.retry()
        }

        return try {
            apiClient.uploadSamples(config.postSamples, uploadedSamples)
            ListenableWorker.Result.success()
        } catch (error: Exception) {
            Log.w(TAG, "Background sync upload failed.", error)
            ListenableWorker.Result.retry()
        }
    }

    private fun resolveStartTime(
        lastSyncMap: Map<HealthDataType, String>,
        dataType: HealthDataType,
        config: BackgroundSyncConfig,
        endTime: Instant
    ): Instant {
        if (config.debugForceFullResync24h) {
            return endTime.minus(MAX_WINDOW)
        }

        val lastSync = lastSyncMap[dataType]?.let { timestamp ->
            try {
                Instant.parse(timestamp)
            } catch (error: Exception) {
                throw IllegalArgumentException("Invalid ISO timestamp for ${dataType.identifier}: $timestamp", error)
            }
        } ?: return endTime.minus(MAX_WINDOW)

        val resolved = if (lastSync.isBefore(endTime.minus(MAX_WINDOW))) {
            lastSync.plus(MAX_WINDOW)
        } else {
            lastSync
        }
        return if (resolved.isAfter(endTime)) endTime else resolved
    }

    companion object {
        private val MAX_WINDOW: Duration = Duration.ofHours(24)
        private const val TAG = "BackgroundHealthSync"
    }
}
