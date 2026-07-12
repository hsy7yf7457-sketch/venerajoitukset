import Foundation

/// Central place for turning speeds into display strings so the UI and the
/// notifications stay consistent. Speed limits are legally defined in km/h.
enum SpeedFormatting {
    static let kmhPerKnot = 1.852
    static let msToKmh = 3.6

    static func limitString(kmh: Int, unit: SpeedUnit) -> String {
        switch unit {
        case .kmh:   return "\(kmh) km/h"
        case .knots: return "\(knots(fromKmh: Double(kmh))) kn"
        }
    }

    /// Speed-limit value formatted for the sign (number only, no unit label).
    static func limitValue(kmh: Int, unit: SpeedUnit) -> String {
        switch unit {
        case .kmh:   return "\(kmh)"
        case .knots: return knots(fromKmh: Double(kmh))
        }
    }

    /// The limit expressed in the *other* unit, for the sign's subtitle: the
    /// official km/h when showing knots, or converted knots when showing km/h.
    static func secondaryLimitString(kmh: Int, unit: SpeedUnit) -> String {
        switch unit {
        case .knots: return "\(kmh) km/h"
        case .kmh:   return "\(knots(fromKmh: Double(kmh))) kn"
        }
    }

    static func unitLabel(_ unit: SpeedUnit) -> String {
        unit == .knots ? "kn" : "km/h"
    }

    /// Full unit name shown under the number on the sign.
    static func unitName(_ unit: SpeedUnit) -> String {
        unit == .knots ? String(localized: "Knots") : "km/h"
    }

    /// Number + full unit name for notifications, e.g. "5.5 solmua" / "10 km/h".
    static func limitFull(kmh: Int, unit: SpeedUnit) -> String {
        "\(limitValue(kmh: kmh, unit: unit)) \(unitName(unit))"
    }

    /// Numeric value + unit label for the live GPS speedometer (same unit as limits).
    static func gpsSpeed(metersPerSecond: Double?, unit: SpeedUnit) -> (value: String, unit: String) {
        guard let ms = metersPerSecond else { return ("--", unitLabel(unit)) }
        switch unit {
        case .knots:
            return (String(format: "%.1f", ms / kmhPerKnot * msToKmh), "kn")
        case .kmh:
            return (String(format: "%.1f", ms * msToKmh), "km/h")
        }
    }

    private static func knots(fromKmh kmh: Double) -> String {
        String(format: "%.1f", kmh / kmhPerKnot)
    }
}
