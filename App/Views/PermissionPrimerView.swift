import SwiftUI

/// Explains why the app needs location and notification access before the system
/// prompts appear. Tapping "Continue" hands off to the coordinator, which fires
/// the requests one at a time.
struct PermissionPrimerView: View {
    @EnvironmentObject private var permissions: PermissionCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .padding(.top, 32)

                    Text("Before we start")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text("This app needs a couple of permissions to keep you informed on the water.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 18) {
                        reason(icon: "location.fill",
                               title: "Location",
                               detail: "Shows the speed limit and restrictions for exactly where you are — even in the background, so you get alerts with the screen off.")
                        reason(icon: "bell.badge.fill",
                               title: "Notifications",
                               detail: "Alerts you when you enter or leave a restricted area, so you don't have to keep watching the screen.")
                    }
                    .padding(.horizontal, 4)

                    alwaysWarning
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                Button {
                    permissions.beginRequests()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button("Not now") { dismiss() }
                    .font(.subheadline)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .interactiveDismissDisabled()
    }

    private var alwaysWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            Text("Important: for alerts to work, allow location access \u{201C}Always\u{201D}. iOS grants \u{201C}While Using\u{201D} first — you may need to return to the home screen after granting access, then reopen the app to enable \u{201C}Always\u{201D}.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func reason(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
