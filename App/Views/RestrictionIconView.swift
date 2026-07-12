import SwiftUI

/// Shows the official Finnish waterway sign for a restriction type, falling back
/// to an SF Symbol chip for types that have no standard pictogram.
struct RestrictionIconView: View {
    let type: RestrictionType
    var size: CGFloat = 56

    var body: some View {
        if type == .speedLimit {
            SpeedLimitBadge(text: "20", size: size)
                .accessibilityLabel(type.title)
        } else if let asset = type.signAsset {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(type.title)
        } else {
            Image(systemName: type.symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(type.tint)
                .frame(width: size, height: size)
                .background(type.tint.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: size * 0.18))
                .accessibilityLabel(type.title)
        }
    }
}

/// Miniature version of the rendered speed-limit sign (white square, thick red
/// border) so the speed limit matches the official-sign style of the others.
private struct SpeedLimitBadge: View {
    let text: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.14).fill(.white)
            RoundedRectangle(cornerRadius: size * 0.14)
                .strokeBorder(SpeedLimitSignView.signRed, lineWidth: size * 0.11)
            Text(text)
                .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, size * 0.14)
        }
        .frame(width: size, height: size)
    }
}
