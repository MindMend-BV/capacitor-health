import Foundation
import HealthKit

final class BackgroundHealthPermissionChecker {
    private let healthStore = HKHealthStore()
    private let emptyWriteTypes = Set<HKSampleType>()

    func isBackgroundSyncSupported() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func hasReadAuthorization(
        for dataTypeIdentifiers: [String],
        completion: @escaping (Bool) -> Void
    ) {
        guard isBackgroundSyncSupported() else {
            completion(false)
            return
        }

        let types: [HealthDataType]
        do {
            types = try HealthDataType.parseMany(dataTypeIdentifiers)
        } catch {
            completion(false)
            return
        }

        guard !types.isEmpty else {
            completion(true)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var allAuthorized = true

        for type in types {
            guard let readSet = try? readAuthorizationObjectTypes(for: type) else {
                allAuthorized = false
                continue
            }

            group.enter()
            healthStore.getRequestStatusForAuthorization(toShare: emptyWriteTypes, read: readSet) { status, error in
                defer { group.leave() }
                if error != nil {
                    lock.lock()
                    allAuthorized = false
                    lock.unlock()
                    return
                }
                if status != .unnecessary {
                    lock.lock()
                    allAuthorized = false
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(allAuthorized)
        }
    }

    private func readAuthorizationObjectTypes(for type: HealthDataType) throws -> Set<HKObjectType> {
        switch type {
        case .bloodPressure:
            var set = Set<HKObjectType>()
            if let systolic = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) {
                set.insert(systolic)
            }
            if let diastolic = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) {
                set.insert(diastolic)
            }
            guard !set.isEmpty else {
                throw HealthManagerError.dataTypeUnavailable(type.rawValue)
            }
            return set
        default:
            let sampleType = try type.sampleType()
            return [sampleType]
        }
    }
}
