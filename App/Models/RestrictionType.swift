import SwiftUI

/// A kind of waterway restriction, keyed by the stable string emitted by
/// `Scripts/refresh_data.py` (derived from Väylävirasto's RAJOITUSTYYPIT codes).
enum RestrictionType: String, CaseIterable, Codable, Identifiable {
    case speedLimit          // 01 Nopeusrajoitus
    case wakeBan             // 02 Aallokon aiheuttamisen kielto
    case windsurfBan         // 03 Purjelautailukielto
    case jetSkiBan           // 04 Vesiskootterilla ajo kielletty
    case motorBan            // 05 Aluksen kulku moottorivoimaa käyttäen kielletty
    case anchoringBan        // 06 Ankkurin käyttökielto
    case mooringBan          // 07 Pysäköimiskielto
    case berthingBan         // 08 Kiinnittymiskielto
    case overtakingBan       // 09 Ohittamiskielto
    case meetingBan          // 10 Kohtaamiskielto
    case speedRecommendation // 11 Nopeussuositus
    case waterSkiBan         // 12 Vesihiihtokielto
    case powerLimit          // 13 Tehorajoitus

    var id: String { rawValue }

    /// Localized label shown in the UI (English source strings are the catalog keys).
    var title: String {
        switch self {
        case .speedLimit:          return String(localized: "Speed limit")
        case .wakeBan:             return String(localized: "No wake")
        case .windsurfBan:         return String(localized: "No windsurfing")
        case .jetSkiBan:           return String(localized: "No jet skis")
        case .motorBan:            return String(localized: "No motor power")
        case .anchoringBan:        return String(localized: "No anchoring")
        case .mooringBan:          return String(localized: "No parking")
        case .berthingBan:         return String(localized: "No mooring")
        case .overtakingBan:       return String(localized: "No overtaking")
        case .meetingBan:          return String(localized: "No meeting")
        case .speedRecommendation: return String(localized: "Speed recommendation")
        case .waterSkiBan:         return String(localized: "No water-skiing")
        case .powerLimit:          return String(localized: "Engine power limit")
        }
    }

    /// Noun form used in notifications so "<name> in effect" / "<name> ended"
    /// reads naturally (the UI `title` uses the sign-style phrasing instead).
    var notificationName: String {
        switch self {
        case .speedLimit:          return String(localized: "Speed limit")
        case .wakeBan:             return String(localized: "Wake ban")
        case .windsurfBan:         return String(localized: "Windsurfing ban")
        case .jetSkiBan:           return String(localized: "Jet ski ban")
        case .motorBan:            return String(localized: "Motor ban")
        case .anchoringBan:        return String(localized: "Anchoring ban")
        case .mooringBan:          return String(localized: "Parking ban")
        case .berthingBan:         return String(localized: "Berthing ban")
        case .overtakingBan:       return String(localized: "Overtaking ban")
        case .meetingBan:          return String(localized: "Meeting ban")
        case .speedRecommendation: return String(localized: "Speed recommendation")
        case .waterSkiBan:         return String(localized: "Water-ski ban")
        case .powerLimit:          return String(localized: "Power limit")
        }
    }

    var symbol: String {
        switch self {
        case .speedLimit:          return "speedometer"
        case .wakeBan:             return "water.waves"
        case .windsurfBan:         return "wind"
        case .jetSkiBan:           return "hare"
        case .motorBan:            return "fuelpump"
        case .anchoringBan:        return "arrow.down.to.line"
        case .mooringBan:          return "parkingsign"
        case .berthingBan:         return "link"
        case .overtakingBan:       return "arrow.left.arrow.right"
        case .meetingBan:          return "arrow.left.and.right.circle"
        case .speedRecommendation: return "gauge.medium"
        case .waterSkiBan:         return "figure.pool.swim"
        case .powerLimit:          return "bolt"
        }
    }

    /// Official Finnish waterway sign (Vesiliikennemerkki, public domain) bundled
    /// in the asset catalog, or nil where no official sign exists.
    /// The speed limit has its own rendered sign; speed recommendation and the
    /// engine-power limit have no standard pictogram, so they fall back to `symbol`.
    var signAsset: String? {
        switch self {
        case .speedLimit, .speedRecommendation, .powerLimit:
            return nil
        default:
            return "sign_\(rawValue)"
        }
    }

    var tint: Color {
        switch self {
        case .speedLimit:          return .red
        case .speedRecommendation: return .blue
        default:                   return .orange
        }
    }

    /// The two types the app surfaces by default (both on the main screen and
    /// as the default notification set).
    static let defaultVisible: Set<RestrictionType> = [.speedLimit, .wakeBan]
    static let defaultNotifying: Set<RestrictionType> = [.speedLimit, .wakeBan]

    /// Ordering used wherever we list every type (settings, chips).
    static var displayOrder: [RestrictionType] {
        [.speedLimit, .wakeBan, .motorBan, .jetSkiBan, .waterSkiBan, .windsurfBan,
         .anchoringBan, .mooringBan, .berthingBan, .overtakingBan, .meetingBan,
         .powerLimit, .speedRecommendation]
    }
}
