import Foundation
import UserNotifications
import QuotaBarApplication

/// Wraps `UNUserNotificationCenter`: request authorization once, post on demand.
/// The decision logic lives in `AlertEngine`; this only delivers.
///
/// Every entry point guards on `Bundle.main.bundleIdentifier` before touching
/// `UNUserNotificationCenter.current()` — that call throws an Obj-C exception
/// (`bundleProxyForCurrentProcess is nil`) when the process has no registered
/// bundle, which happens when running the raw SPM binary or an unsigned Xcode
/// debug build that hasn't been granted a bundle identifier by the system.
@MainActor
final class NotificationService {
    private var authorized = false

    init() {}

    nonisolated func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.authorized = granted
            }
        }
    }

    func post(decision: AlertEngine.Decision, providerName: String) {
        guard authorized, Bundle.main.bundleIdentifier != nil else { return }
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
        content.title = "QuotaBar"
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func postCustom(title: String, body: String) {
        guard authorized, Bundle.main.bundleIdentifier != nil else { return }
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
