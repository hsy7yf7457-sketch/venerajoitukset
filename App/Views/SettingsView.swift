import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: RestrictionStore
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $settings.speedUnit) {
                        ForEach(SpeedUnit.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Speed units")
                } footer: {
                    Text("Used for both the speedometer and the limit. Limits are legally defined in km/h; knots are converted and rounded.")
                }

                Section {
                    Toggle(isOn: speedingBinding) {
                        Text("Speeding warning")
                    }
                } header: {
                    Text("Speeding")
                } footer: {
                    Text("Alerts you (even in the background) when you go more than 10% over the limit. Starts 10 seconds after entering a speed-limit zone. Requires location set to \u{201C}Always\u{201D}.")
                }

                Section {
                    ForEach(RestrictionType.displayOrder) { type in
                        Toggle(isOn: notifyBinding(type)) {
                            typeLabel(type)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get a local alert when you enter and when you leave a zone. Requires location set to \u{201C}Always\u{201D}.")
                }

                Section {
                    Stepper(value: $settings.speedometerMax, in: 10...120, step: 5) {
                        HStack {
                            Text("Maximum speed")
                            Spacer()
                            Text(verbatim: "\(settings.speedometerMax) \(SpeedFormatting.unitLabel(settings.speedUnit))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Speedometer")
                } footer: {
                    Text("Full-scale value of the gauge. The number keeps counting above it, but the arc stays at the maximum.")
                }

                Section {
                    ForEach(RestrictionType.displayOrder.filter { $0 != .speedLimit }) { type in
                        Toggle(isOn: visibleBinding(type)) {
                            typeLabel(type)
                        }
                    }
                } header: {
                    Text("Show on main screen")
                } footer: {
                    Text("The speed limit always shows as the large sign. These control the smaller restriction icons.")
                }

                Section("Data") {
                    if let date = store.generatedAt {
                        LabeledContent("Updated", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("Areas", value: "\(store.areas.count)")
                    LabeledContent("Source", value: "Väylävirasto")
                    Link("Open data licence (CC BY 4.0)",
                         destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func typeLabel(_ type: RestrictionType) -> some View {
        HStack(spacing: 12) {
            RestrictionIconView(type: type, size: 30)
            Text(type.title)
        }
    }

    private func notifyBinding(_ type: RestrictionType) -> Binding<Bool> {
        Binding(get: { settings.isNotifying(type) },
                set: { on in
                    settings.setNotifying(type, on)
                    if on && notifications.authorization == .notDetermined {
                        notifications.requestAuthorization()
                    }
                })
    }

    private func visibleBinding(_ type: RestrictionType) -> Binding<Bool> {
        Binding(get: { settings.isVisible(type) },
                set: { settings.setVisible(type, $0) })
    }

    private var speedingBinding: Binding<Bool> {
        Binding(get: { settings.speedingWarningEnabled },
                set: { on in
                    settings.speedingWarningEnabled = on
                    if on && notifications.authorization == .notDetermined {
                        notifications.requestAuthorization()
                    }
                })
    }
}
