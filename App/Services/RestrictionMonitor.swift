import Combine
import CoreLocation
import Foundation

/// A restriction type currently in force at the user's position, plus the
/// area(s) responsible (used for the detail sheet).
struct ActiveRestriction: Identifiable {
    let type: RestrictionType
    let areas: [RestrictionArea]
    var id: String { type.rawValue }
    var exception: String? { areas.compactMap(\.exception).first }
    var info: String? { areas.compactMap(\.info).first }
    var name: String? { areas.compactMap(\.name).first }
}

/// The brain of the app: watches location, resolves the active restrictions,
/// publishes them for the UI, and fires enter/leave notifications.
@MainActor
final class RestrictionMonitor: ObservableObject {
    @Published private(set) var currentSpeedLimit: Int?
    @Published private(set) var speedLimitHasException = false
    @Published private(set) var activeRestrictions: [ActiveRestriction] = []
    @Published private(set) var activeSpeedArea: RestrictionArea?

    private let store: RestrictionStore
    private let settings: AppSettings
    private let location: LocationManager
    private let notifications: NotificationManager
    private var cancellables: Set<AnyCancellable> = []

    // Notification hysteresis. The UI updates on every fix, but a notification
    // only fires once a *new* resolved state has held continuously for
    // `confirmationInterval`. This absorbs the enter/exit/enter flapping caused
    // by GPS noise right on a zone boundary.
    private var baselineEstablished = false
    /// State we have already announced.
    private var confirmedLimit: Int?
    private var confirmedTypes: Set<RestrictionType> = []
    /// Most recent raw reading and the moment it first appeared.
    private var rawLimit: Int?
    private var rawTypes: Set<RestrictionType> = []
    private var rawStableSince = Date()
    private let confirmationInterval: TimeInterval = 8

    // Speeding warning. Edge-triggered with hysteresis so GPS noise near the
    // limit doesn't spam: it fires once when crossing 110% of the limit and only
    // re-arms after the speed drops back to the limit. A grace period after
    // entering a zone gives time to slow down first.
    private var speedingLimit: Int?
    private var speedingZoneSince: Date?
    private var isSpeeding = false
    private let speedingGrace: TimeInterval = 10

    init(store: RestrictionStore,
         settings: AppSettings,
         location: LocationManager,
         notifications: NotificationManager) {
        self.store = store
        self.settings = settings
        self.location = location
        self.notifications = notifications

        location.$location
            .sink { [weak self] loc in self?.handle(location: loc) }
            .store(in: &cancellables)

        // The 14 MB dataset loads asynchronously; if the first GPS fix arrives
        // before it's ready, re-evaluate the current position once it's loaded.
        store.$isLoaded
            .filter { $0 }
            .sink { [weak self] _ in self?.handle(location: self?.location.location) }
            .store(in: &cancellables)
    }

    private func handle(location loc: CLLocation?) {
        guard let loc, store.isLoaded else { return }
        // Ignore fixes the OS flags as invalid; they're a common noise source.
        guard loc.horizontalAccuracy >= 0 else { return }
        let coord = loc.coordinate

        let areas = store.activeAreas(at: coord)

        // Strictest (lowest) speed limit among all containing areas.
        let speedAreas = areas.filter { $0.codes.contains(.speedLimit) && $0.speed != nil }
        let strictest = speedAreas.min { ($0.speed ?? .max) < ($1.speed ?? .max) }
        let newLimit = strictest?.speed

        // All restriction types active here, grouped to their areas.
        var byType: [RestrictionType: [RestrictionArea]] = [:]
        for area in areas {
            for type in area.codes {
                byType[type, default: []].append(area)
            }
        }
        let activeTypes = Set(byType.keys)

        // Publish UI state (chips exclude the speed limit, which has its own sign).
        currentSpeedLimit = newLimit
        activeSpeedArea = strictest
        speedLimitHasException = speedAreas.contains { $0.exception != nil }
        activeRestrictions = RestrictionType.displayOrder
            .filter { $0 != .speedLimit && settings.isVisible($0) && byType[$0] != nil }
            .map { ActiveRestriction(type: $0, areas: byType[$0] ?? []) }

        emitNotifications(newLimit: newLimit, activeTypes: activeTypes)
        evaluateSpeeding(limit: newLimit, speedMS: loc.speed, now: Date())
    }

    /// Warns (foreground or background) when the boat exceeds 110% of the limit.
    /// Starts checking only after `speedingGrace` seconds in the zone.
    private func evaluateSpeeding(limit: Int?, speedMS: Double, now: Date) {
        guard settings.speedingWarningEnabled else {
            speedingLimit = nil
            speedingZoneSince = nil
            isSpeeding = false
            return
        }

        // Reset the grace timer and armed state whenever the limit value changes
        // (entering a new zone, or leaving into open water).
        if limit != speedingLimit {
            speedingLimit = limit
            speedingZoneSince = limit == nil ? nil : now
            isSpeeding = false
        }

        guard let limit, let since = speedingZoneSince else { return }
        guard now.timeIntervalSince(since) >= speedingGrace else { return }
        guard speedMS >= 0 else { return }

        let speedKmh = speedMS * SpeedFormatting.msToKmh
        let trigger = Double(limit) * 1.10
        let rearm = Double(limit)   // must fall back to the limit before warning again

        if !isSpeeding, speedKmh > trigger {
            isSpeeding = true
            let speedValue = SpeedFormatting.gpsSpeed(metersPerSecond: speedMS, unit: settings.speedUnit)
            let limitValue = SpeedFormatting.limitFull(kmh: limit, unit: settings.speedUnit)
            notifications.post(
                title: "",
                body: String(localized: "Overspeed: \(speedValue.value) \(speedValue.unit) — limit \(limitValue)"),
                alert: .speeding)
        } else if isSpeeding, speedKmh <= rearm {
            isSpeeding = false
        }
    }

    private func emitNotifications(newLimit: Int?,
                                   activeTypes: Set<RestrictionType>) {
        let now = Date()

        // First fix just establishes a silent baseline (avoids a launch storm).
        guard baselineEstablished else {
            baselineEstablished = true
            confirmedLimit = newLimit
            confirmedTypes = activeTypes
            rawLimit = newLimit
            rawTypes = activeTypes
            rawStableSince = now
            return
        }

        // Restart the dwell timer whenever the raw reading changes. Flapping on a
        // boundary keeps resetting this, so it never reaches the threshold.
        if newLimit != rawLimit || activeTypes != rawTypes {
            rawLimit = newLimit
            rawTypes = activeTypes
            rawStableSince = now
            return
        }

        // Reading has held steady; wait until it's been stable long enough, then
        // announce only if it actually differs from what we last confirmed.
        guard now.timeIntervalSince(rawStableSince) >= confirmationInterval else { return }
        guard newLimit != confirmedLimit || activeTypes != confirmedTypes else { return }

        // Collect every change from this transition into one notification; these
        // are often bundled (e.g. a speed limit that also bans wake), so a single
        // period-delimited line reads better than several separate alerts.
        var lines: [String] = []
        // Whether this transition brings any restriction into force. If so it's a
        // "begin" alert; if it only lifts restrictions it's an "end" alert.
        var hasEntering = false

        // Speed limit: single short line on enter / change / leave.
        if settings.isNotifying(.speedLimit), newLimit != confirmedLimit {
            if let limit = newLimit {
                let value = SpeedFormatting.limitFull(kmh: limit, unit: settings.speedUnit)
                lines.append(String(localized: "Speed limit \(value)"))
                hasEntering = true
            } else {
                lines.append(String(localized: "Speed limit ended"))
            }
        }

        // Other toggled restriction types: "<name> in effect" / "<name> ended".
        for type in RestrictionType.displayOrder where type != .speedLimit {
            guard settings.isNotifying(type) else { continue }
            let isActive = activeTypes.contains(type)
            let wasActive = confirmedTypes.contains(type)
            if isActive && !wasActive {
                lines.append(String(localized: "\(type.notificationName) in effect"))
                hasEntering = true
            } else if !isActive && wasActive {
                lines.append(String(localized: "\(type.notificationName) ended"))
            }
        }

        if !lines.isEmpty {
            // Put the message in the body: it wraps to multiple lines, whereas the
            // title is a single truncated line. The app name shows in the header.
            // Combined messages read better with a trailing period; a lone line
            // looks cleaner without one.
            let body = lines.count > 1 ? lines.joined(separator: ". ") + "." : lines[0]
            notifications.post(title: "", body: body,
                               alert: hasEntering ? .begin : .end)
        }

        confirmedLimit = newLimit
        confirmedTypes = activeTypes
    }
}
