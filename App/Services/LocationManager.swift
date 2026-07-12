import CoreLocation
import Foundation
import UIKit

/// Wraps `CLLocationManager`. Location tracking starts automatically; background
/// updates are enabled only when the user has granted "Always" so enter/leave
/// alerts keep working with the screen off.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorization: CLAuthorizationStatus
    /// Device heading in degrees (0 = true north), nil when unavailable.
    @Published private(set) var heading: CLLocationDirection?

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 1
            manager.startUpdatingHeading()
        }
        // Keep the reported heading relative to the top of the *screen* so the
        // compass stays correct after the UI rotates into landscape.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateHeadingOrientation()
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateHeadingOrientation() }
        }
    }

    /// Aligns CoreLocation's heading reference with the current interface
    /// orientation. Only the orientations the app supports are applied; when the
    /// device lies flat (face up/down) the previous value is kept.
    private func updateHeadingOrientation() {
        let orientation: CLDeviceOrientation
        switch UIDevice.current.orientation {
        case .portrait:            orientation = .portrait
        case .landscapeLeft:       orientation = .landscapeLeft
        case .landscapeRight:      orientation = .landscapeRight
        case .portraitUpsideDown:  orientation = .portrait  // UI stays portrait
        default:                   return
        }
        manager.headingOrientation = orientation
    }

    /// GPS ground speed in m/s (nil when unavailable/invalid).
    var speedMetersPerSecond: Double? {
        guard let s = location?.speed, s >= 0 else { return nil }
        return s
    }

    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    /// Begins tracking if permission is already granted. Does *not* prompt; the
    /// permission request is driven separately by the primer so requests can be
    /// explained and sequenced. Idempotent.
    func start() {
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            beginUpdates()
        }
    }

    /// Shows the system location prompt. Asks for "Always" so enter/leave alerts
    /// keep working with the screen off.
    func requestAuthorization() {
        guard authorization == .notDetermined else { return }
        manager.requestAlwaysAuthorization()
    }

    private func beginUpdates() {
        if authorization == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.location = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateHeading newHeading: CLHeading) {
        // Prefer true (geographic) north; fall back to magnetic when uncalibrated.
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading
                                                : newHeading.magneticHeading
        guard value >= 0 else { return }
        Task { @MainActor in self.heading = value }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.beginUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are expected; nothing to do but wait for the next fix.
    }
}
