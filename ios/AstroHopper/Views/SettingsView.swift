import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showHelp = false
    @State private var editingList = false
    @State private var listText = ""
    @State private var listErrors = ""
    @State private var editingObjects = false
    @State private var objectsText = ""
    @State private var objectErrors: [String] = []
    @State private var search = ""

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Settings (\(version))").bold()
                    Spacer()
                    Button("?") { showHelp = true }.buttonStyle(.hopperSquare)
                    Button("X") { dismiss() }.buttonStyle(.hopperSquare)
                }
                HStack(spacing: 16) {
                    Button("↻") { model.resetAll() }
                        .buttonStyle(.hopperSquare)
                        .accessibilityLabel("Reset alignment and target")
                    CheckBox(title: "Small UI", isOn: $model.smallUI).fixedSize()
                    CheckBox(title: "Night", isOn: $model.nightMode).fixedSize()
                }

                IncDec(title: "FOV", value: "∠\(Int(model.fov))°", dec: model.zoomOut, inc: model.zoomIn)
                IncDec(title: "Stars", value: "m≤\(model.starMag)",
                       dec: { model.starMag = max(1, model.starMag - 1) },
                       inc: { model.starMag = min(6, model.starMag + 1) })
                IncDec(title: "DSO", value: "m≤\(model.dsoMag)",
                       dec: { model.dsoMag = max(3, model.dsoMag - 1) },
                       inc: { model.dsoMag = min(14, model.dsoMag + 1) })
                HStack {
                    Text("List").frame(width: 64, alignment: .leading)
                    Button("<", action: model.prevWatchList).buttonStyle(.hopperSquare)
                    Button(">", action: model.nextWatchList).buttonStyle(.hopperSquare)
                    Text(model.currentListName)
                    Spacer()
                    Button(editingList ? "[hide]" : "[edit]") {
                        if !editingList { listText = model.watchListText }
                        editingList.toggle()
                    }
                }
                if editingList { watchListEditor }
                IncDec(title: "Font", value: "+\(model.fontBoost)mm",
                       dec: { model.fontBoost = max(0, model.fontBoost - 1) },
                       inc: { model.fontBoost = min(10, model.fontBoost + 1) })

                HStack {
                    TextField("Find object", text: $search)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { if model.findTarget(search) { dismiss() } }
                        .onChange(of: search) { _, v in model.findTarget(v) }
                        .padding(.horizontal, 6)
                        .frame(height: 10 * pointsPerMM)
                        .overlay(RoundedRectangle(cornerRadius: 2 * pointsPerMM).stroke(Color.ui, lineWidth: 2))
                    Text(model.target?.name ?? "").bold()
                        .frame(minWidth: 80, alignment: .trailing)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        CheckBox(title: "Align on DSO", isOn: $model.alignOnDSO)
                        CheckBox(title: "Star Names", isOn: $model.showStarNames)
                    }
                    GridRow {
                        CheckBox(title: "Open Clusters", isOn: shown(.openCluster))
                        CheckBox(title: "Glob. Clusters", isOn: shown(.globularCluster))
                    }
                    GridRow {
                        CheckBox(title: "Nebulae", isOn: shown(.nebula))
                        CheckBox(title: "Galaxies", isOn: shown(.galaxy))
                    }
                    GridRow {
                        CheckBox(title: "Planets", isOn: shown(.planet))
                        CheckBox(title: "Constellations", isOn: shown(.constellation))
                    }
                    GridRow {
                        CheckBox(title: "Show Tutorial", isOn: $model.showTutorial)
                        CheckBox(title: "Pinch Zoom", isOn: $model.pinchZoom)
                    }
                }
                HStack {
                    Text("Wiki:")
                    Picker("Wiki", selection: $model.wikiMode) {
                        ForEach(WikiMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    CheckBox(title: "User Objects", isOn: shown(.user)).fixedSize()
                    Spacer()
                    Button(editingObjects ? "[hide]" : "[edit]") {
                        if !editingObjects { objectsText = model.userObjectsText }
                        editingObjects.toggle()
                    }
                }
                if editingObjects { userObjectsEditor }

                Divider().overlay(Color.ui)
                HStack {
                    Button("↻") { model.location.refresh() }
                        .buttonStyle(.hopperSquare)
                        .accessibilityLabel("Refresh location")
                    Text("GPS: " + (model.location.hasFix
                        ? Format.dms(model.location.latitude, positive: "N", negative: "S") + ", "
                            + Format.dms(model.location.longitude, positive: "E", negative: "W")
                        : "Unknown"))
                }
                TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                    Text(debugLine(tl.date)).font(.system(size: 3.5 * pointsPerMM, design: .monospaced))
                }
            }
            .padding()
        }
        .font(.system(size: 4.5 * pointsPerMM))
        .foregroundStyle(Color.ui)
        .tint(Color.ui)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHelp) {
            HelpView().presentationBackground(.black)
        }
    }

    private func shown(_ t: ObjectType) -> Binding<Bool> {
        Binding(get: { model.shown[t] ?? true }, set: { model.shown[t] = $0 })
    }

    private var watchListEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("name: dso1, dso2, dso3, …").italic()
            HopperTextEditor(text: $listText)
            HStack {
                Button("Save") {
                    let notFound = model.saveWatchList(listText)
                    if notFound.isEmpty {
                        listErrors = ""
                        editingList = false
                    } else {
                        listErrors = "Not Found: " + notFound.joined(separator: ", ")
                    }
                }
                .buttonStyle(.hopper)
                Button("Discard") {
                    listErrors = ""
                    editingList = false
                }
                .buttonStyle(.hopper)
            }
            if !listErrors.isEmpty { Text(listErrors) }
        }
    }

    private var userObjectsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name,RA(hh:mm:ss),DE(±dd:mm:ss)").italic()
            HopperTextEditor(text: $objectsText)
            HStack {
                Button("Save") {
                    objectErrors = model.saveUserObjects(objectsText)
                    if objectErrors.isEmpty { editingObjects = false }
                }
                .buttonStyle(.hopper)
                Button("Discard") {
                    objectErrors = []
                    editingObjects = false
                }
                .buttonStyle(.hopper)
            }
            if !objectErrors.isEmpty {
                Text("Errors:").bold()
                ForEach(Array(objectErrors.enumerated()), id: \.offset) { i, e in
                    Text("\(i + 1). \(e)")
                }
            }
        }
    }

    private func debugLine(_ date: Date) -> String {
        let m = model.motion
        let (beta, gamma) = Attitude.betaGamma(ofTilt: m.tilt)
        func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "No" }
        let utc = date.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: .gmt, calendar: Calendar(identifier: .gregorian)))
        return "α=\(f(m.isAvailable ? m.gyroAlpha : nil)) β=\(f(beta)) γ=\(f(gamma)) C=\(f(m.compassAlpha)) UTC=\(utc)"
    }
}
