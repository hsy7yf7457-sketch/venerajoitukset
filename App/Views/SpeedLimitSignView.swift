import SwiftUI

/// The round, red-bordered speed-limit sign. Shows "no limit" state when there
/// is no active speed restriction at the current position.
struct SpeedLimitSignView: View {
    let limit: Int?
    let hasException: Bool
    let unit: SpeedUnit
    var side: CGFloat = 130

    /// Red used on the official Finnish waterway signs (#e51f13).
    static let signRed = Color(red: 0.898, green: 0.122, blue: 0.075)

    var body: some View {
        VStack(spacing: 8) {
            let corner = side * 0.06
            let border = side * 0.10
            ZStack {
                RoundedRectangle(cornerRadius: corner).fill(.white)
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(limit == nil ? Color.secondary.opacity(0.4) : Self.signRed,
                                  lineWidth: border)
                if let limit {
                    VStack(spacing: 0) {
                        Text(SpeedFormatting.limitValue(kmh: limit, unit: unit))
                            .font(.system(size: side * 0.34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text(SpeedFormatting.unitName(unit))
                            .font(.system(size: side * 0.10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.horizontal, side * 0.16)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.31, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
            .overlay(alignment: .topTrailing) {
                if hasException {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .padding(6)
                        .background(.white, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }

            if let limit {
                Text(SpeedFormatting.secondaryLimitString(kmh: limit, unit: unit))
                    .font(.system(size: side * 0.135, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("No speed limit here")
                    .font(.system(size: side * 0.135))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(limit == nil
                            ? "No speed limit here"
                            : "Speed limit \(SpeedFormatting.limitString(kmh: limit!, unit: unit))"
                              + (hasException ? ", exceptions apply" : ""))
    }
}
