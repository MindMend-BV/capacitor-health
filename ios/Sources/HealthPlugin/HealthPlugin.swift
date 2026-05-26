import Foundation
import Capacitor

@objc(HealthPlugin)
public class HealthPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.4.10"
    public let identifier = "HealthPlugin"
    public let jsName = "Health"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "readSamples", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveSample", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openHealthConnectSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showPrivacyPolicy", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryWorkouts", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryAggregated", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "configureBackgroundSync", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startBackgroundSync", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopBackgroundSync", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getBackgroundSyncStatus", returnType: CAPPluginReturnPromise)
    ]

    private let implementation = Health()
    private let backgroundPreferences = BackgroundHealthPreferences()
    private let backgroundPermissionChecker = BackgroundHealthPermissionChecker()
    private let backgroundSyncEngine = BackgroundHealthSyncEngine.shared

    public override func load() {
        backgroundSyncEngine.restoreIfNeeded()
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(implementation.availabilityPayload())
    }

    @objc func requestAuthorization(_ call: CAPPluginCall) {
        let read = (call.getArray("read") as? [String]) ?? []
        let write = (call.getArray("write") as? [String]) ?? []

        implementation.requestAuthorization(readIdentifiers: read, writeIdentifiers: write) { result in
            DispatchQueue.main.async {
                switch result {
                case let .success(payload):
                    call.resolve(payload.toDictionary())
                case let .failure(error):
                    call.reject(error.localizedDescription, nil, error)
                }
            }
        }
    }

    @objc func checkAuthorization(_ call: CAPPluginCall) {
        let read = (call.getArray("read") as? [String]) ?? []
        let write = (call.getArray("write") as? [String]) ?? []

        implementation.checkAuthorization(readIdentifiers: read, writeIdentifiers: write) { result in
            DispatchQueue.main.async {
                switch result {
                case let .success(payload):
                    call.resolve(payload.toDictionary())
                case let .failure(error):
                    call.reject(error.localizedDescription, nil, error)
                }
            }
        }
    }

    @objc func readSamples(_ call: CAPPluginCall) {
        guard let dataType = call.getString("dataType") else {
            call.reject("dataType is required")
            return
        }

        let startDate = call.getString("startDate")
        let endDate = call.getString("endDate")
        let limit = call.getInt("limit")
        let ascending = call.getBool("ascending") ?? false

        do {
            try implementation.readSamples(
                dataTypeIdentifier: dataType,
                startDateString: startDate,
                endDateString: endDate,
                limit: limit,
                ascending: ascending
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case let .success(samples):
                        call.resolve(["samples": samples])
                    case let .failure(error):
                        call.reject(error.localizedDescription, nil, error)
                    }
                }
            }
        } catch {
            call.reject(error.localizedDescription, nil, error)
        }
    }

    @objc func saveSample(_ call: CAPPluginCall) {
        guard let dataType = call.getString("dataType") else {
            call.reject("dataType is required")
            return
        }

        guard let value = call.getDouble("value") else {
            call.reject("value is required")
            return
        }

        let unit = call.getString("unit")
        let startDate = call.getString("startDate")
        let endDate = call.getString("endDate")
        let metadataAny = call.getObject("metadata") as? [String: Any]
        let metadata = metadataAny?.reduce(into: [String: String]()) { result, entry in
            if let stringValue = entry.value as? String {
                result[entry.key] = stringValue
            }
        }
        
        let systolic = call.getDouble("systolic")
        let diastolic = call.getDouble("diastolic")

        do {
            try implementation.saveSample(
                dataTypeIdentifier: dataType,
                value: value,
                unitIdentifier: unit,
                startDateString: startDate,
                endDateString: endDate,
                metadata: metadata,
                systolic: systolic,
                diastolic: diastolic
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        call.resolve()
                    case let .failure(error):
                        call.reject(error.localizedDescription, nil, error)
                    }
                }
            }
        } catch {
            call.reject(error.localizedDescription, nil, error)
        }
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }

    @objc func openHealthConnectSettings(_ call: CAPPluginCall) {
        // No-op on iOS - Health Connect is Android only
        call.resolve()
    }

    @objc func showPrivacyPolicy(_ call: CAPPluginCall) {
        // No-op on iOS - Health Connect privacy policy is Android only
        call.resolve()
    }

    @objc func queryWorkouts(_ call: CAPPluginCall) {
        let workoutType = call.getString("workoutType")
        let startDate = call.getString("startDate")
        let endDate = call.getString("endDate")
        let limit = call.getInt("limit")
        let ascending = call.getBool("ascending") ?? false
        let anchor = call.getString("anchor")

        implementation.queryWorkouts(
            workoutTypeString: workoutType,
            startDateString: startDate,
            endDateString: endDate,
            limit: limit,
            ascending: ascending,
            anchorString: anchor
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case let .success(response):
                    call.resolve(response)
                case let .failure(error):
                    call.reject(error.localizedDescription, nil, error)
                }
            }
        }
    }

    @objc func queryAggregated(_ call: CAPPluginCall) {
        guard let dataType = call.getString("dataType") else {
            call.reject("dataType is required")
            return
        }

        let startDate = call.getString("startDate")
        let endDate = call.getString("endDate")
        let bucket = call.getString("bucket")
        let aggregation = call.getString("aggregation")

        implementation.queryAggregated(
            dataTypeIdentifier: dataType,
            startDateString: startDate,
            endDateString: endDate,
            bucketString: bucket,
            aggregationString: aggregation
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case let .success(response):
                    call.resolve(response)
                case let .failure(error):
                    call.reject(error.localizedDescription, nil, error)
                }
            }
        }
    }

    @objc func configureBackgroundSync(_ call: CAPPluginCall) {
        guard backgroundPermissionChecker.isBackgroundSyncSupported() else {
            call.resolve(unavailableBackgroundSyncStatus())
            return
        }

        do {
            var config = try parseBackgroundSyncConfig(from: call)
            if let existing = backgroundPreferences.getConfig() {
                config.enabled = existing.enabled
            }
            try backgroundPreferences.saveConfig(config)
            resolveBackgroundSyncStatus(config: config, call: call)
        } catch {
            call.reject(error.localizedDescription, nil, error)
        }
    }

    @objc func startBackgroundSync(_ call: CAPPluginCall) {
        guard backgroundPermissionChecker.isBackgroundSyncSupported() else {
            call.resolve(unavailableBackgroundSyncStatus())
            return
        }

        do {
            var config = try backgroundPreferences.requireConfig()
            backgroundSyncEngine.checkPermissions(for: config) { [weak self] hasReadPermissions in
                guard let self = self else { return }
                guard hasReadPermissions else {
                    call.reject("Background sync requires HealthKit read permissions for all configured dataTypes.")
                    return
                }

                self.backgroundSyncEngine.deliveryManagerForPlugin.start(config: config) { deliveryOk in
                    guard deliveryOk else {
                        call.reject("Background sync requires HealthKit background delivery for all configured dataTypes.")
                        return
                    }

                    config = config.withEnabled(true)
                    do {
                        try self.backgroundPreferences.saveConfig(config)
                        BackgroundHealthTaskScheduler.schedule(config: config)
                        self.resolveBackgroundSyncStatus(config: config, call: call, permissionsGranted: true)
                    } catch {
                        call.reject(error.localizedDescription, nil, error)
                    }
                }
            }
        } catch {
            call.reject(error.localizedDescription, nil, error)
        }
    }

    @objc func stopBackgroundSync(_ call: CAPPluginCall) {
        let clearConfiguration = call.getBool("clearConfiguration") ?? false

        backgroundSyncEngine.deliveryManagerForPlugin.stop()
        BackgroundHealthTaskScheduler.cancel()

        if clearConfiguration {
            backgroundPreferences.clearConfiguration()
            call.resolve([
                "isBgSyncAvailable": backgroundPermissionChecker.isBackgroundSyncSupported(),
                "isBgPermissionsGranted": false,
                "isBgSyncScheduled": false
            ])
            return
        }

        backgroundPreferences.setEnabled(false)
        let config = backgroundPreferences.getConfig()
        resolveBackgroundSyncStatus(config: config, call: call)
    }

    @objc func getBackgroundSyncStatus(_ call: CAPPluginCall) {
        guard backgroundPermissionChecker.isBackgroundSyncSupported() else {
            call.resolve(unavailableBackgroundSyncStatus())
            return
        }

        let config = backgroundPreferences.getConfig()
        resolveBackgroundSyncStatus(config: config, call: call)
    }

    private func resolveBackgroundSyncStatus(
        config: BackgroundSyncConfig?,
        call: CAPPluginCall,
        permissionsGranted: Bool? = nil
    ) {
        guard let config = config else {
            backgroundSyncEngine.buildStatus(config: nil, permissionsGranted: false) { payload in
                DispatchQueue.main.async {
                    call.resolve(payload)
                }
            }
            return
        }

        if let permissionsGranted = permissionsGranted {
            backgroundSyncEngine.buildStatus(config: config, permissionsGranted: permissionsGranted) { payload in
                DispatchQueue.main.async {
                    call.resolve(payload)
                }
            }
            return
        }

        backgroundSyncEngine.checkPermissions(for: config) { granted in
            self.backgroundSyncEngine.buildStatus(config: config, permissionsGranted: granted) { payload in
                DispatchQueue.main.async {
                    call.resolve(payload)
                }
            }
        }
    }

    private func unavailableBackgroundSyncStatus() -> [String: Any] {
        [
            "isBgSyncAvailable": false,
            "isBgPermissionsGranted": false,
            "isBgSyncScheduled": false
        ]
    }

    private func parseBackgroundSyncConfig(from call: CAPPluginCall) throws -> BackgroundSyncConfig {
        var payload: [String: Any] = [:]

        if let subjectId = call.getString("subjectId") {
            payload["subjectId"] = subjectId
        }
        if let interval = call.getString("interval") {
            payload["interval"] = interval
        }
        if let getLastSync = call.getObject("getLastSync") as? [String: Any] {
            payload["getLastSync"] = getLastSync
        }
        if let postSamples = call.getObject("postSamples") as? [String: Any] {
            payload["postSamples"] = postSamples
        }
        if let dataTypes = call.getArray("dataTypes") as? [String] {
            payload["dataTypes"] = dataTypes
        } else if let dataTypes = call.getArray("dataTypes") {
            payload["dataTypes"] = dataTypes.compactMap { $0 as? String }
        }

        return try BackgroundSyncConfig.from(pluginCall: payload)
    }
}
