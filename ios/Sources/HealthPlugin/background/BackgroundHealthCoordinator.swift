import Foundation
import HealthKit

enum BackgroundHealthRunOutcome {
    case success
    case retry
}

final class BackgroundHealthCoordinator {
    private let preferences: BackgroundHealthPreferences
    private let apiClient: BackgroundHealthApiClient
    private let isoFormatter: ISO8601DateFormatter
    private static let maxWindow: TimeInterval = 24 * 60 * 60

    init(
        preferences: BackgroundHealthPreferences = BackgroundHealthPreferences(),
        apiClient: BackgroundHealthApiClient = BackgroundHealthApiClient()
    ) {
        self.preferences = preferences
        self.apiClient = apiClient
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter = formatter
    }

    func run(health: Health, completion: @escaping (BackgroundHealthRunOutcome) -> Void) {
        guard let config = preferences.getConfig(), config.enabled else {
            completion(.success)
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.retry)
            return
        }

        apiClient.fetchLastSyncMap(config: config.getLastSync, subjectId: config.subjectId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .failure(error):
                NSLog("[BackgroundHealthSync] Failed fetching last-sync state: \(error)")
                completion(.retry)
            case let .success(lastSyncMap):
                self.readAndUpload(config: config, health: health, lastSyncMap: lastSyncMap, completion: completion)
            }
        }
    }

    private func readAndUpload(
        config: BackgroundSyncConfig,
        health: Health,
        lastSyncMap: [String: String],
        completion: @escaping (BackgroundHealthRunOutcome) -> Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var uploadedSamples: [[String: Any]] = []
        var successfulReadCount = 0

        for identifier in config.dataTypes {
            let window = resolveReadWindow(lastSyncMap: lastSyncMap, dataTypeIdentifier: identifier)
            group.enter()
            do {
                try health.readSamples(
                    dataTypeIdentifier: identifier,
                    startDateString: isoFormatter.string(from: window.start),
                    endDateString: isoFormatter.string(from: window.end),
                    limit: 0,
                    ascending: true
                ) { result in
                    defer { group.leave() }
                    switch result {
                    case let .success(samples):
                        lock.lock()
                        successfulReadCount += 1
                        uploadedSamples.append(contentsOf: samples)
                        lock.unlock()
                    case let .failure(error):
                        NSLog(
                            "[BackgroundHealthSync] Read failed for \(identifier). Continuing with partial upload. \(error)"
                        )
                    }
                }
            } catch {
                NSLog("[BackgroundHealthSync] Read setup failed for \(identifier): \(error)")
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .utility)) {
            if successfulReadCount == 0 {
                completion(.retry)
                return
            }
            if uploadedSamples.isEmpty {
                completion(.success)
                return
            }

            self.apiClient.uploadSamples(
                config: config.postSamples,
                subjectId: config.subjectId,
                samples: uploadedSamples
            ) { uploadResult in
                switch uploadResult {
                case .success:
                    completion(.success)
                case let .failure(error):
                    NSLog("[BackgroundHealthSync] Upload failed: \(error)")
                    completion(.retry)
                }
            }
        }
    }

    private func resolveReadWindow(lastSyncMap: [String: String], dataTypeIdentifier: String) -> (start: Date, end: Date) {
        let now = Date()
        guard let raw = lastSyncMap[dataTypeIdentifier] else {
            let startOfToday = Calendar.current.startOfDay(for: now)
            return (startOfToday, now)
        }

        guard let lastSync = isoFormatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
            let startOfToday = Calendar.current.startOfDay(for: now)
            return (startOfToday, now)
        }

        let cutoff = now.addingTimeInterval(-Self.maxWindow)
        if lastSync < cutoff {
            return (lastSync, lastSync.addingTimeInterval(Self.maxWindow))
        }
        return (lastSync, now)
    }
}
