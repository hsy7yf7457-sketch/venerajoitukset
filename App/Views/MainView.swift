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
        VStack(spacing: 24) {
            gaugeStack(scale: 1)
            signView()
            restrictionChips
            Spacer()
            permissionButton
            dataFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
                VStack(spacing: 14) {
                    signView(side: signSide)
                    permissionButton
                }
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
        case .denied, .restricted, .authorizedWhenInUse: return true
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
        case .authorizedWhenInUse:
            banner(icon: "location", text: "Background alerts need location access set to \u{201C}Always\u{201D}. Tap to open Settings.", color: .orange)
                .onTapGesture { openSystemSettings() }
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

    @ViewBuilder private var permissionButton: some View {
        switch location.authorization {
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

    /// Speeding when the GPS speed is more than 10% over the active limit.
    /// The limit is legally in km/h, so the comparison is done in km/h.
    private var isOverLimit: Bool {
        guard let limit = monitor.currentSpeedLimit,
              let ms = location.speedMetersPerSecond else { return false }
        return ms * SpeedFormatting.msToKmh > Double(limit) * 1.10
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
