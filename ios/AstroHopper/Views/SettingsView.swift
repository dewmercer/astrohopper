import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Binding var showOnboarding: Bool
    @State private var confirmReset = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Toggle("Night Mode", isOn: $model.nightMode)
                    Toggle("Star Names", isOn: $model.showStarNames)
                    Toggle("Pinch to Zoom", isOn: $model.pinchZoom)
                    ValueStepper(title: "Label Size", value: model.fontBoost == 0 ? "Standard" : "+\(model.fontBoost)",
                                 decrement: { model.fontBoost = max(0, model.fontBoost - 1) },
                                 increment: { model.fontBoost = min(10, model.fontBoost + 1) })
                } header: {
                    Text("Display")
                } footer: {
                    Text("Night mode shows everything in red to protect your dark adaptation.")
                }
                .themedRow(theme)

                Section {
                    ValueStepper(title: "Stars", value: "m ≤ \(model.starMag)",
                                 decrement: { model.starMag = max(1, model.starMag - 1) },
                                 increment: { model.starMag = min(6, model.starMag + 1) })
                    ValueStepper(title: "Deep-Sky Objects", value: "m ≤ \(model.dsoMag)",
                                 decrement: { model.dsoMag = max(3, model.dsoMag - 1) },
                                 increment: { model.dsoMag = min(14, model.dsoMag + 1) })
                } header: {
                    Text("Faintest Magnitude")
                } footer: {
                    Text("Fainter objects are hidden from the map. Only shown stars can be used for alignment.")
                }
                .themedRow(theme)

                Section("Show on Map") {
                    Toggle("Planets", isOn: shown(.planet))
                    Toggle("Constellations", isOn: shown(.constellation))
                    Toggle("Open Clusters", isOn: shown(.openCluster))
                    Toggle("Globular Clusters", isOn: shown(.globularCluster))
                    Toggle("Nebulae", isOn: shown(.nebula))
                    Toggle("Galaxies", isOn: shown(.galaxy))
                    Toggle("User Objects", isOn: shown(.user))
                }
                .themedRow(theme)

                Section {
                    NavigationLink {
                        TextListEditor(
                            title: "Watch Lists",
                            initialText: model.watchListText,
                            placeholder: "clusters: M41, M47, M50",
                            help: """
                            Separate object names with spaces, commas or new lines. Start a named list with \
                            "name:". Add a comment in parentheses after an object, and use commas when names \
                            contain spaces.

                            clusters: M41 (near Sirius), M47, M50
                            doubles: Polaris, "Cor Caroli"
                            """,
                            errorTitle: "Not Found",
                            save: model.saveWatchList)
                    } label: {
                        LabeledContent("Watch Lists", value: "\(model.watchList.names.count)")
                    }
                    NavigationLink {
                        TextListEditor(
                            title: "User Objects",
                            initialText: model.userObjectsText,
                            placeholder: "V1405, 23h 24m 48s, +61° 11′ 15″",
                            help: """
                            One object per line: name, right ascension, declination. Use decimal degrees \
                            or hours/degrees with minutes and optional seconds.

                            V1405, 23h 24m 48s, +61° 11′ 15″
                            Pluto, 19:55:16, -22:13:42
                            """,
                            errorTitle: "Errors",
                            save: model.saveUserObjects)
                    } label: {
                        LabeledContent("User Objects", value: "\(model.catalog.count - model.catalog.userObjectsStart)")
                    }
                } header: {
                    Text("Lists")
                }
                .themedRow(theme)

                Section {
                    Toggle("Align on Deep-Sky Objects", isOn: $model.alignOnDSO)
                    Button("Reset Alignment and Target", role: .destructive) { confirmReset = true }
                        .confirmationDialog("Reset alignment and clear the target?", isPresented: $confirmReset,
                                            titleVisibility: .visible) {
                            Button("Reset", role: .destructive) { model.resetAll() }
                        }
                } header: {
                    Text("Alignment")
                } footer: {
                    Text("Aligning on a large object such as an open cluster is less precise, because its center is hard to pinpoint.")
                }
                .themedRow(theme)

                Section {
                    Picker("Wikipedia Button", selection: $model.wikiMode) {
                        ForEach(WikiMode.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("Wikipedia pages are bright and need an internet connection.")
                }
                .themedRow(theme)

                Section("Help") {
                    NavigationLink("User Guide") { HelpView() }
                    Button("Show Quick Start") {
                        dismiss()
                        showOnboarding = true
                    }
                    Toggle("Show Quick Start at Launch", isOn: $model.showTutorial)
                }
                .themedRow(theme)

                Section {
                    LabeledContent("Latitude", value: model.location.hasFix
                        ? Format.dms(model.location.latitude, positive: "N", negative: "S") : "Unknown")
                    LabeledContent("Longitude", value: model.location.hasFix
                        ? Format.dms(model.location.longitude, positive: "E", negative: "W") : "Unknown")
                    Button("Update Location") { model.location.refresh() }
                    TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                        LabeledContent("Sensors") {
                            Text(sensorLine(tl.date))
                                .font(.caption.monospacedDigit())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Location and Sensors")
                } footer: {
                    if !model.location.authorized {
                        Text("Allow location access in Settings › Privacy & Security › Location Services so the sky matches where you are.")
                    }
                }
                .themedRow(theme)

                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("AstroHopper by Artyom Beilis. Free software under the GNU GPL v3.")
                }
                .themedRow(theme)
            }
            .themedForm(theme)
            .themedTitle("Settings", theme, large: true)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                .themedBackground(theme)
            }
        }
    }

    private func shown(_ t: ObjectType) -> Binding<Bool> {
        Binding(get: { model.shown[t] ?? true }, set: { model.shown[t] = $0 })
    }

    private func sensorLine(_ date: Date) -> String {
        let m = model.motion
        let (beta, gamma) = Attitude.betaGamma(ofTilt: m.tilt)
        func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "–" }
        let utc = date.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: .gmt, calendar: Calendar(identifier: .gregorian)))
        return "α \(f(m.isAvailable ? m.gyroAlpha : nil))  β \(f(beta))  γ \(f(gamma))\ncompass \(f(m.compassAlpha))  UTC \(utc)"
    }
}

/// Edits a text-format list (watch lists, user objects) and saves it only
/// when it parses without errors.
struct TextListEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initialText: String
    let placeholder: String
    let help: String
    let errorTitle: String
    let save: @MainActor (String) -> [String]
    @State private var text = ""
    @State private var errors: [String] = []
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 220)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.body.monospaced())
                                .foregroundStyle(theme.secondary.opacity(0.6))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } footer: {
                Text(help)
            }
            .themedRow(theme)

            if !errors.isEmpty {
                Section(errorTitle) {
                    ForEach(Array(errors.enumerated()), id: \.offset) { _, e in
                        Label(e, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(theme.night ? Color.red : Color.orange)
                    }
                }
                .themedRow(theme)
            }
        }
        .themedForm(theme)
        .themedTitle(title, theme)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    errors = save(text)
                    if errors.isEmpty { dismiss() }
                }
                .disabled(text == initialText)
            }
            .themedBackground(theme)
        }
        .onAppear {
            if !loaded {
                text = initialText
                loaded = true
            }
        }
    }
}
