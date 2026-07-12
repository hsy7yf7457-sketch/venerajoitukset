import SwiftUI

/// Full-bleed reproduction of the static launch image, picking the portrait or
/// landscape artwork to match the current orientation.
struct SplashView: View {
    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height >= geo.size.width
            Image(portrait ? "SplashPortrait" : "SplashLandscape")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}
