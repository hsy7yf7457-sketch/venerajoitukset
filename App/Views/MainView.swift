import CoreLocation
import SwiftUI
import UIKit

struct MainView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: RestrictionStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var monitor: RestrictionMonitor
    @EnvironmentObject private var permissions: PermissionCoordinator

    @State private var showSettings = false
    @State private var showMap = false
    @State private var selectedRestriction: ActiveRestriction?
    @State private var showSpeedException = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                Group {
                    if landscape { landscapeLayout(geo.size) } else { portraitLayout }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) { warnings }
            }
            .navigationTitle("Marine Limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showMap = true } label: { Image(systemName: "map") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showMap) { MapScreen() }
            .sheet(item: $selectedRestriction) { RestrictionDetailSheet(restriction: $0) }
            .sheet(isPresented: $showSpeedException) {
                if let area = monitor.activeSpeedArea {
                    RestrictionDetailSheet(restriction:
                        ActiveRestriction(type: .speedLimit, areas: [area]))
                }
            }
        }
    }

    // MARK: - Layouts

    private var portraitLayout: some View {
        // Scrolls when active restrictions make the content taller than the
        // viewport; otherwise the Spacer pins the button and footer to the bottom.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    gaugeStack(scale: 1)
                    signView()
                    restrictionChips
                    Spacer(minLength: 0)
                    controlButton
                    dataFooter
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height - 32)
                .padding(16)
            }
        }
    }

    private func landscapeLayout(_ size: CGSize) -> some View {
        // Fill the available height with the gauge; the sign scales alongside it.
        let available = max(size.height - 40, 160)
        let gaugeSide = min(available, size.width * 0.5)
        let signSide = min(gaugeSide * 0.60, size.width * 0.34)
        return VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                gaugeStack(scale: gaugeSide / 340)
                    .frame(maxWidth: .infinity)
                circleControlButton
                signView(side: signSide)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            dataFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .overlay(alignment: .topTrailing) {
            cornerChips.padding(.top, 4)
        }
    }

    // MARK: - Building blocks

    private func gaugeStack(scale: CGFloat) -> some View {
        ZStack {
            CompassView(heading: location.heading)
            SpeedometerView(speedMetersPerSecond: location.speedMetersPerSecond,
                            unit: settings.speedUnit,
                            maxScale: settings.speedometerMax,
                            isOverLimit: isOverLimit)
        }
        .scaleEffect(scale, anchor: .center)
        .frame(width: 340 * scale, height: 340 * scale)
    }

    private func signView(side: CGFloat = 130) -> some View {
        SpeedLimitSignView(limit: monitor.currentSpeedLimit,
                           hasException: monitor.speedLimitHasException,
                           unit: settings.speedUnit,
                           side: side)
            .onTapGesture { if monitor.speedLimitHasException { showSpeedException = true } }
            .animation(.easeInOut(duration: 0.35), value: monitor.currentSpeedLimit)
            .animation(.easeInOut(duration: 0.35), value: monitor.speedLimitHasException)
    }

    private var showsLocationWarning: Bool {
        switch location.authorization {
        case .denied, .restricted: return true
        // Provisional Always reports `.authorizedAlways`, so trust `hasFullAlways`
        // rather than the status enum to decide whether to nudge for real Always.
        case .authorizedAlways, .authorizedWhenInUse: return !location.hasFullAlways
        default: return false
        }
    }

    private var showsNotificationWarning: Bool {
        notifications.authorization == .denied
    }

    /// Warning banners, pinned just below the navigation bar via `safeAreaInset`
    /// so they never sit under the toolbar buttons. Empty when nothing's wrong.
    @ViewBuilder private var warnings: some View {
        if showsLocationWarning || showsNotificationWarning {
            VStack(spacing: 8) {
                locationWarning
                if showsNotificationWarning {
                    banner(icon: "bell.slash",
                           text: "Notifications are off. Enable them in Settings to get zone alerts.",
                           color: .orange)
                        .onTapGesture { openSystemSettings() }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder private var locationWarning: some View {
        switch location.authorization {
        case .denied, .restricted:
            banner(icon: "location.slash", text: "Location access is off. Enable it in Settings to see your speed limit.", color: .red)
        case .authorizedAlways, .authorizedWhenInUse:
            if !location.hasFullAlways {
                banner(icon: "location", text: "Background alerts only work if you allow location access \u{201C}Always\u{201D}. Tap to open Settings.", color: .orange)
                    .onTapGesture { openSystemSettings() }
            }
        default:
            EmptyView()
        }
    }

    private func banner(icon: String, text: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var restrictionChips: some View {
        if monitor.activeRestrictions.isEmpty {
            EmptyView()
        } else {
            let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(monitor.activeRestrictions) { r in
                    Button { selectedRestriction = r } label: {
                        VStack(spacing: 5) {
                            RestrictionIconView(type: r.type, size: 58)
                                .overlay(alignment: .topTrailing) {
                                    if r.exception != nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .background(.white, in: Circle())
                                            .offset(x: 4, y: -4)
                                    }
                                }
                            Text(r.type.title)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8),
                       value: monitor.activeRestrictions.map(\.id))
        }
    }

    /// The primary button under the sign: pause/continue while tracking, or a
    /// permission prompt when location access is missing.
    @ViewBuilder private var controlButton: some View {
        switch location.authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            Button { location.isPaused ? location.resume() : location.pause() } label: {
                Label(location.isPaused ? "Continue" : "Pause",
                      systemImage: location.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(location.isPaused ? .green : .accentColor)
        case .notDetermined:
            Button { permissions.showsPrimer = true } label: {
                Label("Allow location access", systemImage: "location.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        case .denied, .restricted:
            Button { openSystemSettings() } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        default:
            EmptyView()
        }
    }

    /// Compact icon-only variant used in landscape, sitting between the gauge and
    /// the sign. Same actions as `controlButton`, just a colored circle.
    @ViewBuilder private var circleControlButton: some View {
        switch location.authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            circleButton(icon: location.isPaused ? "play.fill" : "pause.fill",
                         tint: location.isPaused ? .green : .accentColor) {
                location.isPaused ? location.resume() : location.pause()
            }
        case .notDetermined:
            circleButton(icon: "location.fill", tint: .accentColor) {
                permissions.showsPrimer = true
            }
        case .denied, .restricted:
            circleButton(icon: "gearshape.fill", tint: .red) { openSystemSettings() }
        default:
            EmptyView()
        }
    }

    private func circleButton(icon: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var cornerChips: some View {
        if !monitor.activeRestrictions.isEmpty {
            VStack(spacing: 10) {
                ForEach(monitor.activeRestrictions) { r in
                    Button { selectedRestriction = r } label: {
                        RestrictionIconView(type: r.type, size: 46)
                            .overlay(alignment: .topTrailing) {
                                if r.exception != nil {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .background(.white, in: Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8),
                       value: monitor.activeRestrictions.map(\.id))
        }
    }

    @ViewBuilder private var dataFooter: some View {
        VStack(spacing: 2) {
            if let date = store.generatedAt {
                Text("Data updated \(date.formatted(date: .abbreviated, time: .omitted))")
            }
            Text("© Väylävirasto · CC BY 4.0")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    /// Speeding when the GPS speed is over the active limit by more than the
    /// user's threshold. The limit is legally in km/h, so the comparison is in km/h.
    private var isOverLimit: Bool {
        guard let limit = monitor.currentSpeedLimit,
              let ms = location.speedMetersPerSecond else { return false }
        return ms * SpeedFormatting.msToKmh > Double(limit) * (1 + Double(settings.speedingThresholdPercent) / 100)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
