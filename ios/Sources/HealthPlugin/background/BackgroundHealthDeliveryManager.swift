import Foundation
import HealthKit

final class BackgroundHealthDeliveryManager {
    private let healthStore = HKHealthStore()
    private let syncQueue = DispatchQueue(label: "capgo.health.background.sync", qos: .utility)
    private var observerQueries: [HKObserverQuery] = []
    private var onSyncRequested: (() -> Void)?

    func setSyncHandler(_ handler: @escaping () -> Void) {
        syncQueue.sync {
            onSyncRequested = handler
        }
    }

    func start(config: BackgroundSyncConfig, completion: @escaping (Bool) -> Void) {
        stop()
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        let frequency = hkUpdateFrequency(for: config.interval)
        let types: [HKSampleType]
        do {
            types = try config.dataTypes.compactMap { identifier -> HKSampleType? in
                guard let dataType = HealthDataType(rawValue: identifier) else { return nil }
                return try dataType.sampleType()
            }
        } catch {
            completion(false)
            return
        }

        guard !types.isEmpty else {
            completion(false)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var allSucceeded = true

        for sampleType in types {
            group.enter()
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: frequency) { success, error in
                if let error = error {
                    NSLog("[BackgroundHealthSync] enableBackgroundDelivery failed: \(error)")
                }
                if !success {
                    lock.lock()
                    allSucceeded = false
                    lock.unlock()
                }
                group.leave()
            }

            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, observerCompletion, error in
                if let error = error {
                    NSLog("[BackgroundHealthSync] Observer error: \(error)")
                }
                observerCompletion()
                self?.requestSync()
            }
            observerQueries.append(query)
            healthStore.execute(query)
        }

        group.notify(queue: .main) {
            completion(allSucceeded)
        }
    }

    func stop() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()

        guard HKHealthStore.isHealthDataAvailable() else { return }

        if let config = BackgroundHealthPreferences().getConfig() {
            for identifier in config.dataTypes {
                guard let dataType = HealthDataType(rawValue: identifier),
                      let sampleType = try? dataType.sampleType() else { continue }
                healthStore.disableBackgroundDelivery(for: sampleType) { _, _ in }
            }
        }
    }

    private func requestSync() {
        syncQueue.async { [weak self] in
            self?.onSyncRequested?()
        }
    }

    private func hkUpdateFrequency(for interval: BackgroundSyncInterval) -> HKUpdateFrequency {
        switch interval {
        case .fifteenMinutes, .thirtyMinutes, .oneHour:
            return .hourly
        case .eightHours, .twentyFourHours:
            return .daily
        }
    }
}
