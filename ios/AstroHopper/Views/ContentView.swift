import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showQuickStart = false
    @State private var wikiURL: URL?
    @State private var lastDrag: CGSize?
    @State private var pinchStartFOV: Double?
    @State private var search = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                sky(size: geo.size)
                controls
                searchOverlay
                if showQuickStart {
                    QuickStartView(isPresented: $showQuickStart)
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .tint(Color.ui)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationBackground(.black)
        }
        .sheet(item: $wikiURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
        .onAppear {
            model.start()
            showQuickStart = model.showTutorial
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.motion.start(trueNorth: model.location.authorized)
                UIApplication.shared.isIdleTimerDisabled = true
            } else if phase == .background {
                model.motion.stop()
            }
        }
        .task {
            while !Task.isCancelled {
                model.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .alert("AstroHopper", isPresented: .constant(model.loadError != nil)) {
            Button("OK") { model.loadError = nil }
        } message: {
            Text(model.loadError ?? "")
        }
    }

    // MARK: Sky map and gestures

    private func sky(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { ctx, canvasSize in
                SkyRenderer(model: model, size: canvasSize, date: timeline.date).draw(&ctx)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                if searching {
                    searchFocused = false
                    return
                }
                model.tap(x: value.location.x, y: value.location.y)
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 4).onChanged { value in
                let prev = lastDrag ?? .zero
                model.drag(dx: value.translation.width - prev.width,
                           dy: value.translation.height - prev.height, size: size)
                lastDrag = value.translation
            }.onEnded { _ in lastDrag = nil }
        )
        .simultaneousGesture(
            MagnifyGesture().onChanged { value in
                if pinchStartFOV == nil { pinchStartFOV = model.fov }
                model.pinch(startFOV: pinchStartFOV!, scale: value.magnification)
            }.onEnded { _ in pinchStartFOV = nil }
        )
    }

    // MARK: Overlay controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if model.smallUI {
                    Button("◎") { model.align() }.buttonStyle(.hopperSquare)
                } else {
                    Button("Align") { model.align() }.buttonStyle(.hopper)
                }
                if let c = model.countdown {
                    Text(String(format: "%.1fs", c))
                }
                Text(model.smallUI ? model.alignStatusTiny : model.alignStatus)
                Spacer()
                if !model.smallUI {
                    searchField
                }
                compassButton
            }
            HStack(spacing: 6) {
                if !model.smallUI {
                    Button("-") { model.zoomOut() }.buttonStyle(.hopperSquare)
                    Button("+") { model.zoomIn() }.buttonStyle(.hopperSquare)
                    Text("∠\(Int(model.fov))°")
                }
                Spacer()
                Button {
                    searchFocused = false
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.hopperSquare)
                .accessibilityLabel("Settings")
            }
            if model.currentList >= 0 {
                HStack(spacing: 6) {
                    Button("<") { model.watchListStep(-1) }.buttonStyle(.hopperSquare)
                    Button(">") { model.watchListStep(1) }.buttonStyle(.hopperSquare)
                }
                Text(model.watchListLabel).italic()
            }
            if model.isWikiAllowed {
                Button {
                    wikiURL = model.wikipediaURL
                } label: {
                    Text("W").font(.system(size: 5 * pointsPerMM, design: .serif))
                }
                .buttonStyle(.hopperSquare)
                .accessibilityLabel("Wikipedia")
            }
            if !model.location.hasFix {
                Text("No Geolocation")
            }
            if model.motion.isDemo {
                Text("No Gyro: drag to move")
            }
        }
        .font(.system(size: 5 * pointsPerMM))
        .foregroundStyle(Color.ui)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var compassButton: some View {
        if !model.compassAvailable {
            Image(systemName: "location.slash")
                .font(.system(size: 5 * pointsPerMM))
                .frame(width: 10 * pointsPerMM, height: 10 * pointsPerMM)
                .accessibilityLabel("No compass")
        } else if model.useCompass {
            Button { model.manualMode() } label: { Image(systemName: "hand.raised") }
                .buttonStyle(.hopperSquare)
                .accessibilityLabel("Switch to manual mode")
        } else {
            Button { model.compassMode() } label: { Image(systemName: "location.north.line") }
                .buttonStyle(.hopperSquare)
                .accessibilityLabel("Switch to compass mode")
        }
    }

    /// Compact search box; tapping it opens the expanded field below.
    private var searchField: some View {
        Button {
            searching = true
        } label: {
            Text(search.isEmpty ? "search" : search)
                .lineLimit(1)
                .font(.system(size: 3.5 * pointsPerMM))
                .padding(.horizontal, 4)
                .frame(width: 18 * pointsPerMM, height: 10 * pointsPerMM, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 2 * pointsPerMM).stroke(Color.ui, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .opacity(searching ? 0 : 1)
    }

    /// While typing, the search box expands across the screen like the web app's.
    @ViewBuilder
    private var searchOverlay: some View {
        if searching {
            HStack {
                TextField("search", text: $search)
                    .focused($searchFocused)
                    .font(.system(size: 5 * pointsPerMM))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { searchFocused = false }
                    .padding(.horizontal, 6)
                    .frame(height: 10 * pointsPerMM)
                    .overlay(RoundedRectangle(cornerRadius: 2 * pointsPerMM).stroke(Color.ui, lineWidth: 2))
                Text(search.trimmingCharacters(in: .whitespaces).isEmpty ? "" : (model.targetIndex != nil ? "✓" : "✗"))
                    .frame(width: 24)
            }
            .font(.system(size: 5 * pointsPerMM))
            .foregroundStyle(Color.ui)
            .padding(.horizontal, 24)
            .padding(.top, 31 * pointsPerMM)
            .onChange(of: search) { _, value in model.findTarget(value) }
            .onChange(of: searchFocused) { _, focused in if !focused { searching = false } }
            .onAppear {
                search = ""
                searchFocused = true
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
