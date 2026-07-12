import SwiftUI

/// Detail for a single active restriction, including the raw Finnish exception
/// text (we deliberately don't parse vessel/time conditions — see README).
struct RestrictionDetailSheet: View {
    let restriction: ActiveRestriction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        RestrictionIconView(type: restriction.type, size: 52)
                        Text(restriction.type.title).font(.headline)
                    }
                    if let name = restriction.name, !name.isEmpty {
                        LabeledContent("Location", value: name)
                    }
                }

                if let info = restriction.info, !info.isEmpty {
                    Section("Details") { Text(info) }
                }

                if let exception = restriction.exception, !exception.isEmpty {
                    Section {
                        Text(exception)
                    } header: {
                        Label("Exceptions apply", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("Some limits only apply to certain vessels, depths or times of day. Read the official text and use your judgement.")
                    }
                }
            }
            .navigationTitle("Restriction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
