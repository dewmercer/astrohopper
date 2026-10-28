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
                    Picker("Alignment Stars", selection: $model.alignStarsRequired) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    LabeledContent("Alignment Stars") {
                        Text(alignmentDescription).foregroundStyle(theme.secondary)
                    }
                    Toggle("Align on Deep-Sky Objects", isOn: $model.alignOnDSO)
                    Button("Reset Alignment and Target", role: .destructive) { confirmReset = true }
                        .confirmationDialog("Reset alignment and clear the target?", isPresented: $confirmReset,
                                            titleVisibility: .visible) {
                            Button("Reset", role: .destructive) { model.resetAll() }
                        }
                } header: {
                    Text("Alignment")
                } footer: {
                    Text("""
                    With 2 or 3 stars, AstroHopper also corrects for a phone that isn't exactly parallel \
                    to the tube, so it stays accurate across the sky. After each star it suggests the next one; \
                    tap Done to stop early. Aligning on a large object such as an open cluster is less precise, \
                    because its center is hard to pinpoint.
                    """)
                }
                .themedRow(theme)

                Section {
                    Toggle("Finder Circle", isOn: $model.finderCircle)
                    if model.finderCircle {
                        ValueStepper(title: "Finder Field", value: Self.degrees(model.finderFOV),
                                     decrement: { model.finderFOV = max(0.5, model.finderFOV - 0.5) },
                                     increment: { model.finderFOV = min(15, model.finderFOV + 0.5) })
                    }
                    Toggle("Eyepiece Circle", isOn: $model.eyepieceCircle)
                    if model.eyepieceCircle {
                        numberField("Telescope Focal Length", value: $model.scopeFocalLength, unit: "mm")
                        numberField("Eyepiece Focal Length", value: $model.eyepieceFocalLength, unit: "mm")
                        numberField("Eyepiece Apparent Field", value: $model.eyepieceAFOV, unit: "°")
                        LabeledContent("True Field") {
                            Text(model.eyepieceFOV.map(Self.degrees) ?? "–").foregroundStyle(theme.secondary)
                        }
                        if let fov = model.eyepieceFOV, fov > 0 {
                            LabeledContent("Magnification") {
                                Text("\(Int((model.scopeFocalLength / model.eyepieceFocalLength).rounded()))×")
                                    .foregroundStyle(theme.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Field of View Circles")
                } footer: {
                    Text("Circles around the center of the map show what your finder and eyepiece see. The phone taps when the target enters each one. A typical 8×50 finder sees about 5°.")
                }
                .themedRow(theme)

                Section {
                    NavigationLink {
                        TelescopeSettingsView()
                    } label: {
                        LabeledContent("Telescope", value: telescopeSummary)
                    }
                } header: {
                    Text("Telescope Control")
                } footer: {
                    Text("Optional GoTo for Celestron mounts with a SkyPortal WiFi module.")
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

    private var telescopeSummary: String {
        let scope = model.telescope
        guard scope.enabled else { return "Off" }
        return scope.isConnected ? "Connected" : "Not Connected"
    }

    private var alignmentDescription: String {
        switch model.alignStarsRequired {
        case 1: "Quick"
        case 2: "Accurate"
        default: "Most Accurate"
        }
    }

    private static func degrees(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(v < 1 ? 2 : 1))) + "°"
    }

    private func numberField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                Text(unit).foregroundStyle(theme.secondary)
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
