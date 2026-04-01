package app.capgo.plugin.health.background

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.health.connect.client.HealthConnectClient
import app.capgo.plugin.health.HealthManager

class BackgroundHealthPermissionChecker(
    private val context: Context,
    private val healthManager: HealthManager
) {
    fun isBackgroundSyncSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    }

    suspend fun hasRequiredPermissions(
        client: HealthConnectClient,
        config: BackgroundSyncConfig
    ): Boolean {
        if (!isBackgroundSyncSupported()) {
            return false
        }
        val grantedHealthPermissions = client.permissionController.getGrantedPermissions()
        val requiredHealthPermissions = healthManager.permissionsFor(config.dataTypes, emptyList())
        return grantedHealthPermissions.containsAll(requiredHealthPermissions) && hasRequiredBackgroundPermissions()
    }

    fun hasRequiredBackgroundPermissions(): Boolean {
        if (!isBackgroundSyncSupported()) {
            return false
        }
        return requiredRuntimePermissions().all { permission ->
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun requiredRuntimePermissions(): List<String> {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            Build.VERSION.SDK_INT < 36
        ) {
            permissions += Manifest.permission.BODY_SENSORS_BACKGROUND
        }
        if (Build.VERSION.SDK_INT >= 36) {
            permissions += "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"
        }
        return permissions
    }
}
