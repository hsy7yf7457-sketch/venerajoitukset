import Foundation

/// Drives the location + notification permission flow. Requests are explained by
/// the primer sheet first, then fired one at a time (location, then
/// notifications) so the system alerts never stack up on top of each other.
@MainActor
final class PermissionCoordinator: ObservableObject {
    /// Presents the explanatory primer sheet.
    @Published var showsPrimer = false

    private let location: LocationManager
    private let notifications: NotificationManager

    init(location: LocationManager, notifications: NotificationManager) {
        self.location = location
        self.notifications = notifications
    }

    /// Called after launch: begins updates if already authorized and, when any
    /// permission is still undecided, shows the primer before requesting.
    func startIfNeeded() {
        location.start()
        notifications.refreshAuthorization { [weak self] in
            guard let self else { return }
            if self.location.authorization == .notDetermined
                || self.notifications.authorization == .notDetermined {
                self.showsPrimer = true
            }
        }
    }

    /// Kicks off the sequential requests. The primer is dismissed right away so
    /// the system prompt takes over the screen; location comes first, and the
    /// notification prompt follows once the location prompt has been answered.
    func beginRequests() {
        showsPrimer = false
        if location.authorization == .notDetermined {
            location.requestAuthorization { [weak self] in
                // iOS silently drops a system alert requested while another is
                // still dismissing, so give the location prompt a beat to clear
                // before asking about notifications.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self?.requestNotifications()
                }
            }
        } else {
            requestNotifications()
        }
    }

    private func requestNotifications() {
        guard notifications.authorization == .notDetermined else { return }
        notifications.requestAuthorization()
    }
}
