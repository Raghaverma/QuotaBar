import Foundation
import UserNotifications
import StatsUsageApplication

/// Wraps `UNUserNotificationCenter`: request authorization once, post on demand.
/// The decision logic lives in `AlertEngine`; this only delivers.
@MainActor
final class NotificationService {
    private var authorized = false

    init() {}

    nonisolated func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.authorized = granted
            }
        }
    }

    func post(decision: AlertEngine.Decision, providerName: String) {
        let body: String
        switch decision {
        case .none:
            return
        case .lowRemaining(let percent):
            body = "\(providerName): only \(Int(percent.rounded()))% remaining."
        case .repeatedFailures(let count):
            body = "\(providerName): \(count) consecutive refresh failures."
        case .authError:
            body = "\(providerName): authentication expired — please re-authorize."
        }
        let content = UNMutableNotificationContent()
        content.title = "StatsUsage"
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func postCustom(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
