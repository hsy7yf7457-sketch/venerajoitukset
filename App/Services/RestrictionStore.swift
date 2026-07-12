import CoreLocation
import Foundation

/// Loads the bundled restriction snapshot and answers point queries.
///
/// With ~1,450 areas a linear scan with a bounding-box pre-check is more than
/// fast enough for once-per-second location updates, so no spatial grid is
/// needed. Loading is done off the main thread because the JSON is ~14 MB.
@MainActor
final class RestrictionStore: ObservableObject {
    @Published private(set) var areas: [RestrictionArea] = []
    @Published private(set) var generatedAt: Date?
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?

    func load() {
        guard !isLoaded else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let (areas, date) = try Self.loadBundledSnapshot()
                await MainActor.run {
                    self.areas = areas
                    self.generatedAt = date
                    self.isLoaded = true
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.loadError = message
                    self.isLoaded = true
                }
            }
        }
    }

    /// Areas that are in force at `date` and geometrically contain `coord`.
    func activeAreas(at coord: CLLocationCoordinate2D, on date: Date = Date()) -> [RestrictionArea] {
        areas.filter { $0.isActive(on: date) && $0.contains(coord) }
    }

    /// Decode + date-parse off the main actor. `nonisolated` so it can run
    /// inside `Task.detached`.
    private nonisolated static func loadBundledSnapshot() throws -> (areas: [RestrictionArea], date: Date?) {
        guard let url = Bundle.main.url(forResource: "restrictions", withExtension: "json") else {
            throw StoreError.missingResource
        }
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(RestrictionSnapshot.self, from: data)
        let date = ISO8601DateFormatter().date(from: snapshot.generatedAt)
        return (snapshot.areas, date)
    }

    private enum StoreError: LocalizedError {
        case missingResource
        var errorDescription: String? {
            switch self {
            case .missingResource: return "restrictions.json is missing from the app bundle."
            }
        }
    }
}
