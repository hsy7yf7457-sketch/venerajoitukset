import CoreLocation
import Foundation
import UIKit

/// Wraps `CLLocationManager`. Location tracking starts automatically; background
/// alerts need real "Always" access, which on iOS 18 is only effective while we
/// hold a `CLServiceSession` with an `.always` goal.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorization: CLAuthorizationStatus
    /// Device heading in degrees (0 = true north), nil when unavailable.
    @Published private(set) var heading: CLLocationDirection?
    /// User-controlled pause. When paused we stop GPS updates entirely, so the
    /// sign, speedometer and alerts all freeze until the user resumes.
    @Published private(set) var isPaused = false
    /// True only when *real* Always is granted. Requesting Always up front yields
    /// a "provisional" Always where `authorization` reports `.authorizedAlways`
    /// even though Settings still say "While Using"; the service-session
    /// `alwaysAuthorizationDenied` diagnostic is the only way to tell them apart.
    @Published private(set) var hasFullAlways = false

    private let manager = CLLocationManager()
    /// Held for the app's lifetime once tracking starts: on iOS 18 Always access
    /// is only effective while an `.always` session is alive, and its diagnostics
    /// drive `hasFullAlways`.
    private var serviceSession: CLServiceSession?
    private var diagnosticsTask: Task<Void, Never>?
    /// One-shot closure fired the first time the authorization prompt resolves,
    /// used to chain the notification request after the location request.
    private var authorizationHandler: (() -> Void)?

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
            ensureServiceSession()
            beginUpdates()
        }
    }

    /// Shows the system location prompt. Requests "Always" so iOS will later
    /// re-prompt to upgrade a provisional grant on its own; `hasFullAlways` still
    /// tells us whether it's the real thing, so the banner stays up until it is.
    /// `completion` runs once the prompt is answered (or immediately if there's
    /// nothing to ask).
    func requestAuthorization(completion: (() -> Void)? = nil) {
        guard authorization == .notDetermined else {
            completion?()
            return
        }
        authorizationHandler = completion
        // Creating the `.always` service session presents the system prompt.
        ensureServiceSession()
    }

    /// Holds a single `.always` service session and mirrors its diagnostics into
    /// `hasFullAlways`. Safe to call repeatedly.
    private func ensureServiceSession() {
        guard serviceSession == nil else { return }
        let session = CLServiceSession(authorization: .always)
        serviceSession = session
        diagnosticsTask = Task { [weak self] in
            do {
                for try await diagnostic in session.diagnostics {
                    // Wait until every location prompt in the flow has settled;
                    // `authorizationRequestInProgress` stays true across both the
                    // "While Using" and the follow-up "Always" prompt.
                    guard !diagnostic.authorizationRequestInProgress else { continue }
                    await MainActor.run {
                        guard let self else { return }
                        self.hasFullAlways = !diagnostic.alwaysAuthorizationDenied
                        // Only now chain the next request (notifications), so it
                        // never appears between the two location prompts.
                        if let handler = self.authorizationHandler {
                            self.authorizationHandler = nil
                            handler()
                        }
                    }
                }
            } catch {
                // Stream ended / session invalidated; nothing to do.
            }
        }
    }

    /// Suspends GPS tracking until `resume()`; the whole UI holds its last state.
    func pause() {
        isPaused = true
        manager.stopUpdatingLocation()
    }

    /// Resumes GPS tracking (if permission is granted).
    func resume() {
        isPaused = false
        start()
    }

    private func beginUpdates() {
        guard !isPaused else { return }
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
        Task { @MainActor in
            // Read the status *inside* the main-actor hop so we always publish the
            // current value even if callbacks arrive close together.
            let status = manager.authorizationStatus
            self.authorization = status
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                self.beginUpdates()
            }
            // The notification hand-off is driven by the service-session
            // diagnostics instead (see `ensureServiceSession`), so it waits for the
            // whole location flow — When-In-Use *and* Always — to finish first.
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are expected; nothing to do but wait for the next fix.
    }
}
