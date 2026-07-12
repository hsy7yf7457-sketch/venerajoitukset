import Foundation

/// Owns the long-lived services and wires them together. Held by the app as a
/// single `@StateObject`; its children are injected into the environment so
/// views observe them directly.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let store: RestrictionStore
    let location: LocationManager
    let notifications: NotificationManager
    let monitor: RestrictionMonitor
    let permissions: PermissionCoordinator

    init() {
        let settings = AppSettings()
        let store = RestrictionStore()
        let location = LocationManager()
        let notifications = NotificationManager()
        self.settings = settings
        self.store = store
        self.location = location
        self.notifications = notifications
        self.monitor = RestrictionMonitor(store: store,
                                          settings: settings,
                                          location: location,
                                          notifications: notifications)
        self.permissions = PermissionCoordinator(location: location,
                                                 notifications: notifications)
    }

    func start() {
        store.load()
    }
}
