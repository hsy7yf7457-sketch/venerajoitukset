import SwiftUI

/// Car-style arc speedometer: a 270° arc with the gap at the bottom (from the
/// 7:30 position clockwise through the top to 4:30). The arc caps out at the
/// configured maximum, but the numeric readout keeps climbing past it.
struct SpeedometerView: View {
    let speedMetersPerSecond: Double?
    let unit: SpeedUnit
    let maxScale: Int
    let isOverLimit: Bool

    /// The drawn arc is 3/4 of a full circle; rotating +135° puts its start at 7:30.
    private let arcPortion: CGFloat = 0.75
    private let arcRotation: Double = 135
    private let lineWidth: CGFloat = 16

    private var primary: (value: String, unit: String) {
        SpeedFormatting.gpsSpeed(metersPerSecond: speedMetersPerSecond, unit: unit)
    }

    private var displaySpeed: Double? {
        guard let ms = speedMetersPerSecond else { return nil }
        return unit == .knots ? ms / SpeedFormatting.kmhPerKnot * SpeedFormatting.msToKmh
                              : ms * SpeedFormatting.msToKmh
    }

    private var fraction: CGFloat {
        guard let d = displaySpeed, maxScale > 0 else { return 0 }
        return min(max(CGFloat(d) / CGFloat(maxScale), 0), 1)
    }

    private var gaugeColor: Color { isOverLimit ? .red : .accentColor }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: arcPortion)
                .stroke(Color.secondary.opacity(0.15),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(arcRotation))

            Circle()
                .trim(from: 0, to: arcPortion * fraction)
                .stroke(gaugeColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(arcRotation))
                .animation(.easeOut(duration: 0.4), value: fraction)
                .animation(.easeInOut(duration: 0.3), value: isOverLimit)

            VStack(spacing: 2) {
                Text(primary.value)
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? Color.red : Color.primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: isOverLimit)
                Text(primary.unit)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if isOverLimit {
                    Text("Overspeed")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.red)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isOverLimit)
        }
        .frame(width: 260, height: 260)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current speed \(primary.value) \(primary.unit)")
    }
}
