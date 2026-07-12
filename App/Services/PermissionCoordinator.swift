import Combine
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
    private var cancellables: Set<AnyCancellable> = []
    /// True while we're waiting for the user to answer the location prompt, so a
    /// stray authorization change from elsewhere doesn't advance the chain.
    private var awaitingLocationResponse = false

    init(location: LocationManager, notifications: NotificationManager) {
        self.location = location
        self.notifications = notifications

        // Continue to the notification request once the location prompt resolves.
        location.$authorization
            .dropFirst()
            .sink { [weak self] _ in self?.locationDidRespond() }
            .store(in: &cancellables)
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
            awaitingLocationResponse = true
            location.requestAuthorization()
        } else {
            requestNotifications()
        }
    }

    private func locationDidRespond() {
        guard awaitingLocationResponse,
              location.authorization != .notDetermined else { return }
        awaitingLocationResponse = false
        requestNotifications()
    }

    private func requestNotifications() {
        guard notifications.authorization == .notDetermined else { return }
        notifications.requestAuthorization()
    }
}
