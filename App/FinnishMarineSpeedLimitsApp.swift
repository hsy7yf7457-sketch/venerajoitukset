import SwiftUI

@main
struct FinnishMarineSpeedLimitsApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model.settings)
                .environmentObject(model.store)
                .environmentObject(model.location)
                .environmentObject(model.notifications)
                .environmentObject(model.monitor)
                .environmentObject(model.permissions)
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    // Re-read permission state on return so the warnings clear
                    // once the user flips the switches in the system Settings app.
                    if phase == .active { model.notifications.refreshAuthorization() }
                }
        }
    }
}
