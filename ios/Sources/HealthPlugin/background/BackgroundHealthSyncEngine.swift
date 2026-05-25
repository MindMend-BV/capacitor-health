import Foundation

/// Shared entry point for HealthKit observer callbacks and BGAppRefreshTask.
public final class BackgroundHealthSyncEngine {
    public static let shared = BackgroundHealthSyncEngine()

    private let health = Health()
    private let preferences = BackgroundHealthPreferences()
    private let coordinator = BackgroundHealthCoordinator()
    private let permissionChecker = BackgroundHealthPermissionChecker()
    private let deliveryManager = BackgroundHealthDeliveryManager()

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
        coordinator.run(health: health) { outcome in
            completion(outcome == .success)
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
