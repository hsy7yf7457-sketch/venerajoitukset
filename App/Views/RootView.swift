import SwiftUI

/// Hosts the main UI behind the launch splash and plays the reveal animation:
/// the splash slides down while the content scales up from 0.7 and fades in from
/// black — all in a single 0.7s ease-in-out pass.
struct RootView: View {
    @EnvironmentObject private var permissions: PermissionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var isRevealed = false
    @State private var splashHidden = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                // Anchor the scale at the top: the splash uncovers downward, so
                // keeping the top edge pinned lets the status-bar area simply fade
                // in with everything else instead of a black gap sliding up.
                MainView()
                    .scaleEffect(isRevealed ? 1.0 : 0.7, anchor: .top)
                    .opacity(isRevealed ? 1.0 : 0.0)

                if !splashHidden {
                    SplashView()
                        .offset(y: isRevealed ? geo.size.height + 200 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $permissions.showsPrimer) {
            PermissionPrimerView()
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear {
            guard !isRevealed else { return }
            withAnimation(.easeInOut(duration: 0.7)) {
                isRevealed = true
            } completion: {
                splashHidden = true
                // Prompt only after the reveal so the primer doesn't fight the
                // splash animation for the screen.
                permissions.startIfNeeded()
            }
        }
    }
}
