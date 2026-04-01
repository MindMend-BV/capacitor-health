package app.capgo.plugin.health.background

import android.content.Context
import org.json.JSONObject

class BackgroundHealthPreferences(context: Context) {
    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getConfig(): BackgroundSyncConfig? {
        val rawConfig = preferences.getString(KEY_CONFIG, null) ?: return null
        return BackgroundSyncConfig.fromJson(JSONObject(rawConfig))
    }

    fun requireConfig(): BackgroundSyncConfig {
        return getConfig() ?: throw IllegalStateException("Background sync is not configured.")
    }

    fun saveConfig(config: BackgroundSyncConfig) {
        preferences.edit().putString(KEY_CONFIG, config.toJson().toString()).apply()
    }

    fun setEnabled(enabled: Boolean) {
        val config = getConfig() ?: return
        saveConfig(config.withEnabled(enabled))
    }

    companion object {
        private const val PREFS_NAME = "capgo_health_background_sync"
        private const val KEY_CONFIG = "background_sync_config"
    }
}
