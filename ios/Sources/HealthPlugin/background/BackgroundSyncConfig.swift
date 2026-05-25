import Foundation

struct BackgroundSyncApiRequestConfig: Codable, Equatable {
    let url: String
    let headers: [String: String]

    static func from(dictionary: [String: Any], key: String) throws -> BackgroundSyncApiRequestConfig {
        guard let raw = dictionary[key] as? [String: Any] else {
            throw BackgroundSyncConfigError.missingKey(key)
        }
        guard let url = raw["url"] as? String, !url.isEmpty else {
            throw BackgroundSyncConfigError.invalidValue("\(key).url")
        }
        var headers: [String: String] = [:]
        if let headersRaw = raw["headers"] as? [String: Any] {
            for (headerKey, value) in headersRaw {
                if let stringValue = value as? String {
                    headers[headerKey] = stringValue
                }
            }
        }
        return BackgroundSyncApiRequestConfig(url: url, headers: headers)
    }
}

enum BackgroundSyncInterval: String, Codable, CaseIterable {
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case oneHour = "1hour"
    case eightHours = "8hours"
    case twentyFourHours = "24hours"

    var intervalMinutes: Int {
        switch self {
        case .fifteenMinutes: return 15
        case .thirtyMinutes: return 30
        case .oneHour: return 60
        case .eightHours: return 480
        case .twentyFourHours: return 1440
        }
    }

    static func from(identifier: String?) -> BackgroundSyncInterval? {
        guard let identifier = identifier else { return nil }
        return BackgroundSyncInterval(rawValue: identifier)
    }
}

struct BackgroundSyncConfig: Codable, Equatable {
    let subjectId: String
    let getLastSync: BackgroundSyncApiRequestConfig
    let postSamples: BackgroundSyncApiRequestConfig
    let dataTypes: [String]
    let interval: BackgroundSyncInterval
    var enabled: Bool

    func withEnabled(_ enabled: Bool) -> BackgroundSyncConfig {
        var copy = self
        copy.enabled = enabled
        return copy
    }

    static func from(pluginCall dictionary: [String: Any]) throws -> BackgroundSyncConfig {
        guard let subjectId = dictionary["subjectId"] as? String, !subjectId.isEmpty else {
            throw BackgroundSyncConfigError.missingKey("subjectId")
        }
        let getLastSync = try BackgroundSyncApiRequestConfig.from(dictionary: dictionary, key: "getLastSync")
        let postSamples = try BackgroundSyncApiRequestConfig.from(dictionary: dictionary, key: "postSamples")
        guard let dataTypesRaw = dictionary["dataTypes"] as? [String], !dataTypesRaw.isEmpty else {
            throw BackgroundSyncConfigError.invalidValue("dataTypes")
        }
        let dataTypes = Array(Set(dataTypesRaw.filter { !$0.isEmpty }))
        guard !dataTypes.isEmpty else {
            throw BackgroundSyncConfigError.invalidValue("dataTypes")
        }
        for identifier in dataTypes {
            guard HealthDataType(rawValue: identifier) != nil else {
                throw BackgroundSyncConfigError.unsupportedDataType(identifier)
            }
        }
        guard let intervalRaw = dictionary["interval"] as? String,
              let interval = BackgroundSyncInterval.from(identifier: intervalRaw) else {
            throw BackgroundSyncConfigError.invalidValue("interval")
        }
        return BackgroundSyncConfig(
            subjectId: subjectId,
            getLastSync: getLastSync,
            postSamples: postSamples,
            dataTypes: dataTypes,
            interval: interval,
            enabled: false
        )
    }
}

enum BackgroundSyncConfigError: LocalizedError {
    case missingKey(String)
    case invalidValue(String)
    case unsupportedDataType(String)

    var errorDescription: String? {
        switch self {
        case let .missingKey(key):
            return "Background sync \(key) configuration is required."
        case let .invalidValue(key):
            return "Background sync \(key) is invalid."
        case let .unsupportedDataType(identifier):
            return "Unsupported background sync data type: \(identifier)"
        }
    }
}
