import CoreLocation
import Foundation

/// One restriction polygon area from Väylävirasto's registry.
struct RestrictionArea: Decodable, Identifiable {
    let id: Int
    let codes: [RestrictionType]
    let speed: Int?
    let name: String?
    let exception: String?
    let info: String?
    let validFrom: String?
    let validTo: String?
    let bbox: BBox
    /// [polygon][ring][point] where ring[0] is the outer boundary, rest are holes.
    /// Each point is stored as (longitude, latitude).
    let polygons: [[[Point2D]]]

    private let validToDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, codes, speed, name, exception, info, validFrom, validTo, bbox, polygons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        let rawCodes = try c.decode([String].self, forKey: .codes)
        codes = rawCodes.compactMap { RestrictionType(rawValue: $0) }
        speed = try c.decodeIfPresent(Int.self, forKey: .speed)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        exception = try c.decodeIfPresent(String.self, forKey: .exception)
        info = try c.decodeIfPresent(String.self, forKey: .info)
        validFrom = try c.decodeIfPresent(String.self, forKey: .validFrom)
        validTo = try c.decodeIfPresent(String.self, forKey: .validTo)

        let box = try c.decode([Double].self, forKey: .bbox)
        bbox = BBox(minLon: box[0], minLat: box[1], maxLon: box[2], maxLat: box[3])

        let rawPolys = try c.decode([[[[Double]]]].self, forKey: .polygons)
        polygons = rawPolys.map { poly in
            poly.map { ring in ring.map { Point2D(lon: $0[0], lat: $0[1]) } }
        }

        validToDate = RestrictionArea.dateParser.date(from: validTo ?? "")
    }

    /// A restriction with a past end date is no longer in force.
    func isActive(on date: Date) -> Bool {
        guard let end = validToDate else { return true }
        return end >= date
    }

    func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        guard bbox.contains(lon: coord.longitude, lat: coord.latitude) else { return false }
        for poly in polygons where Self.point(coord, insidePolygon: poly) {
            return true
        }
        return false
    }

    /// Inside if within the outer ring and outside every hole ring.
    private static func point(_ coord: CLLocationCoordinate2D, insidePolygon poly: [[Point2D]]) -> Bool {
        guard let outer = poly.first, ringContains(coord, outer) else { return false }
        for hole in poly.dropFirst() where ringContains(coord, hole) {
            return false
        }
        return true
    }

    /// Standard ray-casting test.
    private static func ringContains(_ coord: CLLocationCoordinate2D, _ ring: [Point2D]) -> Bool {
        let x = coord.longitude, y = coord.latitude
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let xi = ring[i].lon, yi = ring[i].lat
            let xj = ring[j].lon, yj = ring[j].lat
            if ((yi > y) != (yj > y)) &&
               (x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'Z'"
        return f
    }()
}

struct Point2D {
    let lon: Double
    let lat: Double
}

struct BBox {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    func contains(lon: Double, lat: Double) -> Bool {
        lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat
    }
}

/// Top-level shape of `restrictions.json`.
struct RestrictionSnapshot: Decodable {
    let source: String
    let attribution: String
    let generatedAt: String
    let crs: String
    let count: Int
    let areas: [RestrictionArea]
}
