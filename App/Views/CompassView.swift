import SwiftUI

/// A compass ring that orbits the speedometer arc. The device heading is kept at
/// the top; marks are only drawn over the 270° arc (7:30 → top → 4:30) and fade
/// to nothing exactly at the two ends of the arc.
struct CompassView: View {
    let heading: Double?

    /// Continuous (unwrapped) heading driving the rotation, so 360°→0° doesn't
    /// spin the ring the long way round and each step animates at constant speed.
    @State private var displayHeading: Double = 0
    @State private var hasHeading = false

    private let size: CGFloat = 340
    /// Ticks start just outside the speedometer arc (its outer edge is ~138pt).
    private let tickBaseline: CGFloat = 140
    private let labelRadius: CGFloat = 163
    /// The arc spans ±135° from the top; the bottom 90° is the empty gap.
    private let arcHalfSpan: Double = 135
    /// Marks start fading this many degrees before the arc end.
    private let fadeWidth: Double = 45

    private var center: CGFloat { size / 2 }

    private struct Mark: Identifiable {
        let id: Int
        let bearing: Double
        let label: String?
        let isCardinal: Bool
        let isInter: Bool
    }

    private static let labels: [Int: String] = [
        0: "N", 45: "NE", 90: "E", 135: "SE",
        180: "S", 225: "SW", 270: "W", 315: "NW"
    ]

    private static let marks: [Mark] = {
        var result: [Mark] = []
        var b = 0
        while b < 360 {
            let cardinal = b % 90 == 0
            let inter = (b % 45 == 0) && !cardinal
            result.append(Mark(id: b,
                               bearing: Double(b),
                               label: labels[b],
                               isCardinal: cardinal,
                               isInter: inter))
            b += 15
        }
        return result
    }()

    var body: some View {
        ZStack {
            if hasHeading {
                // The whole ring is a single rotating transform (cheap + smooth);
                // marks sit at fixed positions and only their opacity tracks the
                // heading so they fade at the arc edges.
                ZStack {
                    ForEach(Self.marks) { tickView($0) }
                    ForEach(Self.marks.filter { $0.label != nil }) { labelView($0) }
                }
                .rotationEffect(.degrees(-displayHeading))
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onAppear { update(heading) }
        .onChange(of: heading) { _, newValue in update(newValue) }
    }

    /// Advances the continuous heading by the shortest signed step and animates
    /// linearly, so rotation reads as steady motion instead of stop-start easing.
    private func update(_ newValue: Double?) {
        guard let newValue else { return }
        guard hasHeading else {
            displayHeading = newValue
            hasHeading = true
            return
        }
        let delta = signedDelta(newValue - displayHeading)
        withAnimation(.linear(duration: 0.25)) {
            displayHeading += delta
        }
    }

    @ViewBuilder
    private func tickView(_ mark: Mark) -> some View {
        let length: CGFloat = mark.isCardinal ? 14 : (mark.isInter ? 11 : 7)
        let width: CGFloat = mark.isCardinal ? 3 : (mark.isInter ? 2 : 1.5)
        let color: Color = mark.isCardinal ? .primary
            : (mark.isInter ? .secondary : Color.secondary.opacity(0.55))

        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .rotationEffect(.degrees(mark.bearing))
            .position(point(angle: mark.bearing, radius: tickBaseline + length / 2))
            .opacity(opacity(for: signedDelta(mark.bearing - displayHeading)))
    }

    @ViewBuilder
    private func labelView(_ mark: Mark) -> some View {
        let isNorth = mark.bearing == 0
        Text(mark.label ?? "")
            .font(mark.isCardinal ? .system(size: 15, weight: .bold, design: .rounded)
                                  : .system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(isNorth ? Color.red : (mark.isCardinal ? .primary : .secondary))
            .rotationEffect(.degrees(mark.bearing))
            .position(point(angle: mark.bearing, radius: labelRadius))
            .opacity(opacity(for: signedDelta(mark.bearing - displayHeading)))
    }

    /// Screen point for an angle measured clockwise from the top (12 o'clock).
    private func point(angle degrees: Double, radius: CGFloat) -> CGPoint {
        let r = Double(radius)
        let rad = degrees * .pi / 180
        return CGPoint(x: Double(center) + r * sin(rad),
                       y: Double(center) - r * cos(rad))
    }

    /// Full inside the arc, fading to zero at the arc ends, zero in the gap.
    private func opacity(for screen: Double) -> Double {
        let a = abs(screen)
        if a >= arcHalfSpan { return 0 }
        let fadeStart = arcHalfSpan - fadeWidth
        if a <= fadeStart { return 1 }
        return (arcHalfSpan - a) / fadeWidth
    }

    /// Reduce an angle to the (-180, 180] range.
    private func signedDelta(_ angle: Double) -> Double {
        var d = angle.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }
}
