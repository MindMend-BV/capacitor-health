import Foundation

/// Shared entry point for HealthKit observer callbacks and BGAppRefreshTask.
public final class BackgroundHealthSyncEngine {
    public static let shared = BackgroundHealthSyncEngine()

    private let health = Health()
    private let preferences = BackgroundHealthPreferences()
    private let coordinator = BackgroundHealthCoordinator()
    private let permissionChecker = BackgroundHealthPermissionChecker()
    private let deliveryManager = BackgroundHealthDeliveryManager()
    private let syncQueue = DispatchQueue(label: "capgo.health.background.sync.coordinator", qos: .utility)
    private var isRunningSync = false

    private init() {
        deliveryManager.setSyncHandler { [weak self] in
            self?.performSync { _ in }
        }
    }

    var deliveryManagerForPlugin: BackgroundHealthDeliveryManager {
        deliveryManager
    }

    public func restoreIfNeeded() {
        guard let config = preferences.getConfig(), config.enabled else { return }
        deliveryManager.start(config: config) { _ in }
        BackgroundHealthTaskScheduler.schedule(config: config)
    }

    public func performSync(completion: @escaping (Bool) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            if self.isRunningSync {
                DispatchQueue.main.async { completion(true) }
                return
            }
            self.isRunningSync = true
            self.coordinator.run(health: self.health) { outcome in
                self.syncQueue.async {
                    self.isRunningSync = false
                }
                let success = outcome == .success
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }

    func buildStatus(
        config: BackgroundSyncConfig?,
        permissionsGranted: Bool,
        completion: @escaping ([String: Any]) -> Void
    ) {
        let isAvailable = permissionChecker.isBackgroundSyncSupported()
        let isScheduled = config?.enabled ?? false
        completion([
            "isBgSyncAvailable": isAvailable,
            "isBgPermissionsGranted": isAvailable && permissionsGranted,
            "isBgSyncScheduled": isScheduled
        ])
    }

    func checkPermissions(for config: BackgroundSyncConfig, completion: @escaping (Bool) -> Void) {
        permissionChecker.hasReadAuthorization(for: config.dataTypes, completion: completion)
    }
}
