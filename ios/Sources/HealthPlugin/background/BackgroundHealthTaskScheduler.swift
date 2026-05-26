import Foundation
import BackgroundTasks

public enum BackgroundHealthTaskScheduler {
    public static let taskIdentifier = "app.capgo.health.background.sync"
    public static let minimumIntervalMinutes = 15

    private static var refreshHandler: ((@escaping (Bool) -> Void) -> Void)?
    private static var isRegistered = false

    /// Must be called from `application(_:didFinishLaunchingWithOptions:)` before the app finishes launching.
    public static func registerAtAppLaunch(
        refreshHandler handler: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        refreshHandler = handler
        guard !isRegistered else { return }
        isRegistered = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
            let run = refreshHandler ?? { completion in completion(true) }
            run { success in
                refreshTask.setTaskCompleted(success: success)
                if let config = BackgroundHealthPreferences().getConfig(), config.enabled {
                    schedule(config: config)
                }
            }
        }
    }

    static func schedule(config: BackgroundSyncConfig) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        let minutes = max(config.interval.intervalMinutes, minimumIntervalMinutes)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(minutes * 60))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("[BackgroundHealthSync] Failed to schedule BGAppRefreshTask: \(error)")
        }
    }

    public static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }
}
