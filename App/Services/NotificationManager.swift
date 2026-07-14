import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for local enter/leave alerts.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    /// Which bundled sound to play. `begin` when a restriction starts, `end`
    /// when the last one clears, `speeding` when going over the limit.
    enum Alert {
        case begin, end, speeding

        var sound: UNNotificationSound {
            switch self {
            case .begin:    return UNNotificationSound(named: UNNotificationSoundName("begin_notification.wav"))
            case .end:      return UNNotificationSound(named: UNNotificationSoundName("end_notification.wav"))
            case .speeding: return UNNotificationSound(named: UNNotificationSoundName("record.caf"))
            }
        }
    }

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        // Become the delegate so alerts (and their sound) still show while the
        // app is in the foreground; iOS otherwise suppresses them when active.
        center.delegate = self
    }

    func refreshAuthorization(completion: (() -> Void)? = nil) {
        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.authorization = settings.authorizationStatus
                completion?()
            }
        }
    }

    func requestAuthorization(completion: (() -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refreshAuthorization(completion: completion) }
        }
    }

    func post(title: String, body: String, alert: Alert) {
        guard authorization == .authorized || authorization == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = alert.sound
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        center.add(request)
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// In the foreground, play only the sound — no banner or Notification Center
    /// entry. When backgrounded this isn't called, so the system shows the banner
    /// as usual.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.sound])
    }
}
