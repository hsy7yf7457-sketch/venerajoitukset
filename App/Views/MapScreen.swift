import MapKit
import SwiftUI

/// Full-screen map that draws the restriction polygons around the visible area,
/// coloured by speed limit (or a distinct colour for "other rules only").
struct MapScreen: View {
    @EnvironmentObject private var store: RestrictionStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var permissions: PermissionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?

    /// Above this width we'd draw too many polygons to stay smooth.
    private let maxSpanDegrees = 1.2
    private let maxPolygons = 800

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomLeading) {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(renderPolygons) { rp in
                        MapPolygon(rp.polygon)
                            .foregroundStyle(rp.color.opacity(0.30))
                            .stroke(rp.color, lineWidth: 1.5)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    visibleRegion = ctx.region
                }

                if isZoomedOut {
                    zoomHint
                } else {
                    legend
                }
            }
            .navigationTitle("Restriction map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: centerOnUser)
        }
    }

    private var isZoomedOut: Bool {
        (visibleRegion?.span.latitudeDelta ?? .greatestFiniteMagnitude) > maxSpanDegrees
    }

    // MARK: Polygon building

    private var renderPolygons: [RenderPolygon] {
        guard let region = visibleRegion, !isZoomedOut else { return [] }
        let box = BBox(minLon: region.center.longitude - region.span.longitudeDelta / 2,
                       minLat: region.center.latitude - region.span.latitudeDelta / 2,
                       maxLon: region.center.longitude + region.span.longitudeDelta / 2,
                       maxLat: region.center.latitude + region.span.latitudeDelta / 2)

        var result: [RenderPolygon] = []
        for area in store.areas where area.isActive(on: Date()) && intersects(area.bbox, box) {
            let color = SpeedPalette.color(for: area)
            for (pIdx, poly) in area.polygons.enumerated() {
                guard let outer = poly.first, outer.count >= 3 else { continue }
                let outerCoords = outer.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let holes = poly.dropFirst().map { ring -> MKPolygon in
                    let c = ring.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    return MKPolygon(coordinates: c, count: c.count)
                }
                let mk = MKPolygon(coordinates: outerCoords, count: outerCoords.count,
                                   interiorPolygons: holes.isEmpty ? nil : holes)
                result.append(RenderPolygon(id: "\(area.id)-\(pIdx)", polygon: mk, color: color))
                if result.count >= maxPolygons { return result }
            }
        }
        return result
    }

    private func intersects(_ a: BBox, _ b: BBox) -> Bool {
        a.minLon <= b.maxLon && a.maxLon >= b.minLon &&
        a.minLat <= b.maxLat && a.maxLat >= b.minLat
    }

    private func centerOnUser() {
        if let coord = location.location?.coordinate {
            let region = MKCoordinateRegion(center: coord,
                                            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))
            position = .region(region)
            visibleRegion = region
        } else {
            position = .userLocation(fallback: .automatic)
        }
        if location.authorization == .notDetermined {
            permissions.showsPrimer = true
        }
    }

    // MARK: Overlays

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speed limit").font(.caption.bold())
            ForEach(SpeedPalette.legend, id: \.label) { entry in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.color.opacity(0.5))
                        .frame(width: 16, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(entry.color, lineWidth: 1))
                    Text(LocalizedStringKey(entry.label)).font(.caption2)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    private var zoomHint: some View {
        Text("Zoom in to show restriction zones")
            .font(.caption)
            .padding(10)
            .background(.regularMaterial, in: Capsule())
            .padding()
    }
}

private struct RenderPolygon: Identifiable {
    let id: String
    let polygon: MKPolygon
    let color: Color
}

/// Colour scale: distinct colour per speed band, and a separate colour for
/// zones with no speed limit but other rules.
enum SpeedPalette {
    static func color(for area: RestrictionArea) -> Color {
        guard let speed = area.speed, area.codes.contains(.speedLimit) else {
            return otherRules
        }
        switch speed {
        case ...10: return .red
        case 11...15: return .orange
        case 16...20: return .yellow
        case 21...25: return .green
        default: return .blue
        }
    }

    static let otherRules = Color.purple

    static let legend: [(label: String, color: Color)] = [
        ("\u{2264} 10 km/h", .red),
        ("11\u{2013}15 km/h", .orange),
        ("16\u{2013}20 km/h", .yellow),
        ("21\u{2013}25 km/h", .green),
        ("26+ km/h", .blue),
        ("Other rules only", otherRules),
    ]
}
