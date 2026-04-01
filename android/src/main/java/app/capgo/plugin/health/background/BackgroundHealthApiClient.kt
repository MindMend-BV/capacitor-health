package app.capgo.plugin.health.background

import app.capgo.plugin.health.HealthDataType
import com.getcapacitor.JSArray
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONArray
import org.json.JSONObject

class BackgroundHealthApiClient {
    fun fetchLastSyncMap(config: BackgroundSyncApiRequestConfig): Map<HealthDataType, String> {
        val connection = openConnection(config, "GET")
        return connection.useJsonConnection { response ->
            val json = JSONObject(response)
            val lastSyncJson = json.optJSONObject("data") ?: json
            buildMap {
                val keys = lastSyncJson.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val dataType = HealthDataType.from(key)
                        ?: throw IllegalArgumentException("Unsupported health data type in last sync response: $key")
                    val timestamp = lastSyncJson.optString(key)
                    if (timestamp.isBlank()) {
                        throw IllegalArgumentException("Missing timestamp for health data type: $key")
                    }
                    put(dataType, timestamp)
                }
            }
        }
    }

    fun uploadSamples(config: BackgroundSyncApiRequestConfig, samples: JSArray) {
        val body = JSONObject().apply {
            put("data", JSONArray(samples.toString()))
        }
        val connection = openConnection(config, "POST")
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        BufferedWriter(OutputStreamWriter(connection.outputStream)).use { writer ->
            writer.write(body.toString())
        }
        connection.useJsonConnection { }
    }

    private fun openConnection(config: BackgroundSyncApiRequestConfig, method: String): HttpURLConnection {
        val connection = (URL(config.url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            instanceFollowRedirects = true
        }
        config.headers.forEach { (key, value) ->
            connection.setRequestProperty(key, value)
        }
        return connection
    }

    private inline fun <T> HttpURLConnection.useJsonConnection(block: (String) -> T): T {
        return try {
            val statusCode = responseCode
            val stream = if (statusCode in 200..299) inputStream else errorStream
            val responseBody = stream?.let { input ->
                BufferedReader(InputStreamReader(input)).use { reader ->
                    reader.readText()
                }
            }.orEmpty()
            if (statusCode !in 200..299) {
                throw IllegalStateException(
                    "Background sync API request failed with status $statusCode." +
                        if (responseBody.isNotBlank()) " Response: $responseBody" else ""
                )
            }
            block(responseBody)
        } finally {
            disconnect()
        }
    }

    companion object {
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 30_000
    }
}
