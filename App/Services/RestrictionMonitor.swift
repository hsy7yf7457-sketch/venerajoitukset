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

    // A boundary crossing must persist for `settleInterval` before we touch the
    // sign/icons *or* notify, so brief GPS jitter across a boundary doesn't flip
    // the display or beep. Visuals and sounds therefore settle together.
    private struct Resolved {
        var limit: Int?
        var types: Set<RestrictionType>
        var strictest: RestrictionArea?
        var hasException: Bool
        var byType: [RestrictionType: [RestrictionArea]]
        /// Boundary identity: only the limit and the active types matter.
        func sameZone(as other: Resolved) -> Bool {
            limit == other.limit && types == other.types
        }
    }
    private var pending: Resolved?
    private var pendingSince = Date()
    private var committed: Resolved?
    private let settleInterval: TimeInterval = 1

    // Speeding warning. Fires when crossing 110% of the limit and then repeats
    // every `speedingRepeat` seconds while still over it; it re-arms once the
    // speed drops back to the limit (hysteresis keeps GPS noise from spamming).
    // A grace period after entering a zone gives time to slow down first.
    private var speedingLimit: Int?
    private var speedingZoneSince: Date?
    private var isSpeeding = false
    private var lastSpeedingWarning = Date.distantPast
    private let speedingGrace: TimeInterval = 10
    private let speedingRepeat: TimeInterval = 5

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

        // All restriction types active here, grouped to their areas.
        var byType: [RestrictionType: [RestrictionArea]] = [:]
        for area in areas {
            for type in area.codes {
                byType[type, default: []].append(area)
            }
        }

        let resolved = Resolved(
            limit: strictest?.speed,
            types: Set(byType.keys),
            strictest: strictest,
            hasException: speedAreas.contains { $0.exception != nil },
            byType: byType)

        settle(resolved, speedMS: loc.speed, now: Date())
    }

    /// Applies a resolved reading — updating the sign/icons and firing enter/leave
    /// notifications together — but only once the new zone has held steady for
    /// `settleInterval`. Speeding is checked every fix against the settled limit.
    private func settle(_ resolved: Resolved, speedMS: Double, now: Date) {
        // A different zone restarts the dwell timer; the same zone just refreshes
        // the payload (keeps the strictest area current) without resetting it.
        if pending == nil || !pending!.sameZone(as: resolved) {
            pendingSince = now
        }
        pending = resolved

        evaluateSpeeding(limit: committed?.limit, speedMS: speedMS, now: now)

        guard now.timeIntervalSince(pendingSince) >= settleInterval else { return }
        guard committed == nil || !committed!.sameZone(as: resolved) else { return }

        let previous = committed
        apply(resolved)
        committed = resolved
        // First settle just establishes a silent baseline (no launch-time beep).
        if let previous { emitNotifications(from: previous, to: resolved) }
    }

    /// Publishes UI state (chips exclude the speed limit, which has its own sign).
    private func apply(_ r: Resolved) {
        currentSpeedLimit = r.limit
        activeSpeedArea = r.strictest
        speedLimitHasException = r.hasException
        activeRestrictions = RestrictionType.displayOrder
            .filter { $0 != .speedLimit && settings.isVisible($0) && r.byType[$0] != nil }
            .map { ActiveRestriction(type: $0, areas: r.byType[$0] ?? []) }
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
        let trigger = Double(limit) * (1 + Double(settings.speedingThresholdPercent) / 100)
        let rearm = Double(limit)   // must fall back to the limit before warning again

        if speedKmh > trigger {
            // Warn on the first crossing, then repeat every `speedingRepeat`s
            // while still speeding.
            if !isSpeeding || now.timeIntervalSince(lastSpeedingWarning) >= speedingRepeat {
                isSpeeding = true
                lastSpeedingWarning = now
                let speedValue = SpeedFormatting.gpsSpeed(metersPerSecond: speedMS, unit: settings.speedUnit)
                let limitValue = SpeedFormatting.limitFull(kmh: limit, unit: settings.speedUnit)
                notifications.post(
                    title: "",
                    body: String(localized: "Overspeed: \(speedValue.value) \(speedValue.unit) — limit \(limitValue)"),
                    alert: .speeding)
            }
        } else if isSpeeding, speedKmh <= rearm {
            isSpeeding = false
        }
    }

    private func emitNotifications(from old: Resolved, to new: Resolved) {
        // Collect every change from this transition into one notification; these
        // are often bundled (e.g. a speed limit that also bans wake), so a single
        // period-delimited line reads better than several separate alerts.
        var lines: [String] = []
        // Whether this transition brings any restriction into force. If so it's a
        // "begin" alert; if it only lifts restrictions it's an "end" alert.
        var hasEntering = false

        // Speed limit: single short line on enter / change / leave.
        if settings.isNotifying(.speedLimit), new.limit != old.limit {
            if let limit = new.limit {
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
            let isActive = new.types.contains(type)
            let wasActive = old.types.contains(type)
            if isActive && !wasActive {
                lines.append(String(localized: "\(type.notificationName) in effect"))
                hasEntering = true
            } else if !isActive && wasActive {
                lines.append(String(localized: "\(type.notificationName) ended"))
            }
        }

        guard !lines.isEmpty else { return }
        // Put the message in the body: it wraps to multiple lines, whereas the
        // title is a single truncated line. The app name shows in the header.
        // Combined messages read better with a trailing period; a lone line
        // looks cleaner without one.
        let body = lines.count > 1 ? lines.joined(separator: ". ") + "." : lines[0]
        notifications.post(title: "", body: body, alert: hasEntering ? .begin : .end)
    }
}
