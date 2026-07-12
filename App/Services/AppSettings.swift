import Foundation
import SwiftUI

enum SpeedUnit: String, CaseIterable, Identifiable {
    case knots
    case kmh

    var id: String { rawValue }
    var label: String {
        switch self {
        case .knots: return String(localized: "knots")
        case .kmh:   return "km/h"
        }
    }
}

/// User preferences, persisted to `UserDefaults`.
///
/// - `visibleTypes`: which restriction types show as icons on the main screen.
/// - `notifyingTypes`: which restriction types fire enter/leave notifications.
@MainActor
final class AppSettings: ObservableObject {
    @Published var visibleTypes: Set<RestrictionType> {
        didSet { persist(visibleTypes, key: Keys.visible) }
    }
    @Published var notifyingTypes: Set<RestrictionType> {
        didSet { persist(notifyingTypes, key: Keys.notifying) }
    }
    @Published var speedUnit: SpeedUnit {
        didSet { defaults.set(speedUnit.rawValue, forKey: Keys.unit) }
    }
    /// Full-scale value of the speedometer arc, in the selected unit.
    @Published var speedometerMax: Int {
        didSet { defaults.set(speedometerMax, forKey: Keys.maxScale) }
    }
    /// Alert (also in the background) when going more than 10% over the limit.
    @Published var speedingWarningEnabled: Bool {
        didSet { defaults.set(speedingWarningEnabled, forKey: Keys.speedingWarning) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.visibleTypes = Self.readSet(defaults, key: Keys.visible)
            ?? RestrictionType.defaultVisible
        self.notifyingTypes = Self.readSet(defaults, key: Keys.notifying)
            ?? RestrictionType.defaultNotifying
        self.speedUnit = SpeedUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "")
            ?? .knots
        self.speedometerMax = (defaults.object(forKey: Keys.maxScale) as? Int) ?? 40
        self.speedingWarningEnabled = (defaults.object(forKey: Keys.speedingWarning) as? Bool) ?? true
    }

    func isVisible(_ type: RestrictionType) -> Bool { visibleTypes.contains(type) }
    func isNotifying(_ type: RestrictionType) -> Bool { notifyingTypes.contains(type) }

    func setVisible(_ type: RestrictionType, _ on: Bool) {
        if on { visibleTypes.insert(type) } else { visibleTypes.remove(type) }
    }
    func setNotifying(_ type: RestrictionType, _ on: Bool) {
        if on { notifyingTypes.insert(type) } else { notifyingTypes.remove(type) }
    }

    private func persist(_ set: Set<RestrictionType>, key: String) {
        defaults.set(set.map(\.rawValue), forKey: key)
    }

    private static func readSet(_ defaults: UserDefaults, key: String) -> Set<RestrictionType>? {
        guard let raw = defaults.array(forKey: key) as? [String] else { return nil }
        return Set(raw.compactMap { RestrictionType(rawValue: $0) })
    }

    private enum Keys {
        static let visible = "settings.visibleTypes"
        static let notifying = "settings.notifyingTypes"
        static let unit = "settings.speedUnit"
        static let maxScale = "settings.speedometerMax"
        static let speedingWarning = "settings.speedingWarning"
    }
}
