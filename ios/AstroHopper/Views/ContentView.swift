import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showOnboarding = false
    @State private var wikiURL: URL?

    private var theme: Theme { Theme(night: model.nightMode) }

    var body: some View {
        ZStack {
            SkyMapView()
                .ignoresSafeArea()
            VStack(spacing: 12) {
                StatusCapsule()
                Spacer()
                HStack {
                    Spacer()
                    ZoomControl()
                }
                if model.target != nil || model.currentList >= 0 {
                    TargetCard(wikiURL: $wikiURL)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                BottomBar(showSearch: $showSearch, showSettings: $showSettings)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .animation(.snappy, value: model.targetIndex)
        }
        .themed(theme)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.success, trigger: model.aligned) { _, aligned in aligned }
        .sensoryFeedback(.selection, trigger: model.targetIndex)
        .sheet(isPresented: $showSettings) {
            SettingsView(showOnboarding: $showOnboarding).themed(theme)
        }
        .sheet(isPresented: $showSearch) {
            SearchView().themed(theme)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView().themed(theme)
        }
        .sheet(item: $wikiURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
        .onAppear {
            model.start()
            showOnboarding = model.showTutorial
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
        .alert("Unable to Load Data", isPresented: .constant(model.loadError != nil)) {
            Button("OK") { model.loadError = nil }
        } message: {
            Text(model.loadError ?? "")
        }
    }
}

// MARK: Sky map

private struct SkyMapView: View {
    @Environment(AppModel.self) private var model
    @State private var lastDrag: CGSize?
    @State private var pinchStartFOV: Double?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { ctx, size in
                    SkyRenderer(model: model, size: size, date: timeline.date).draw(&ctx)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    model.tap(x: value.location.x, y: value.location.y)
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4).onChanged { value in
                    let prev = lastDrag ?? .zero
                    model.drag(dx: value.translation.width - prev.width,
                               dy: value.translation.height - prev.height, size: geo.size)
                    lastDrag = value.translation
                }.onEnded { _ in lastDrag = nil }
            )
            .simultaneousGesture(
                MagnifyGesture().onChanged { value in
                    if pinchStartFOV == nil { pinchStartFOV = model.fov }
                    model.pinch(startFOV: pinchStartFOV!, scale: value.magnification)
                }.onEnded { _ in pinchStartFOV = nil }
            )
            .accessibilityLabel("Sky map")
            .accessibilityHint(model.waitingForAlign ? "Tap the star the telescope points at" : "Tap an object to select it")
        }
    }
}

// MARK: Status

private struct StatusCapsule: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                status
                if model.selectMode != .target {
                    Button("Cancel") { model.cancelAlign() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .floatingBackground(theme, in: Capsule())

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 0.2)) { tl in
                    let p = model.pointing(at: tl.date)
                    Text("Alt \(p.alt, format: .number.precision(.fractionLength(1)))°  Az \(p.az, format: .number.precision(.fractionLength(1)))°")
                        .monospacedDigit()
                }
                if !model.location.hasFix {
                    Label("No Location", systemImage: "location.slash")
                }
                if model.motion.isDemo {
                    Label("Demo: Drag to Move", systemImage: "hand.draw")
                }
            }
            .font(.caption)
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .floatingBackground(theme, in: Capsule())
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var status: some View {
        switch model.selectMode {
        case .countdown:
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(theme.secondary.opacity(0.4), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: (model.countdown ?? 0) / 3)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                Text("Hold steady on \(model.alignObject?.displayName ?? "star")…")
            }
            .font(.subheadline.weight(.semibold))
        case .align:
            Label("Tap the star you're pointing at", systemImage: "scope")
                .font(.subheadline.weight(.semibold))
        case .target:
            if model.aligned {
                Label("Aligned on \(model.alignObject?.displayName ?? "star")", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            } else {
                Label("Not Aligned", systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.secondary)
            }
        }
    }
}

// MARK: Zoom

private struct ZoomControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Button { model.zoomIn() } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zoom In")
            Text("\(Int(model.fov))°")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondary)
                .accessibilityLabel("Field of view \(Int(model.fov)) degrees")
            Button { model.zoomOut() } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zoom Out")
        }
        .font(.body.weight(.semibold))
        .floatingBackground(theme, in: Capsule())
    }
}

// MARK: Target card

private struct TargetCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Binding var wikiURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let target = model.target {
                header(target)
                TimelineView(.periodic(from: .now, by: 0.1)) { tl in
                    direction(model.pointing(at: tl.date))
                }
            } else if let item = model.currentWatchItem {
                Label("\(item.name) is not in the catalog", systemImage: "questionmark.circle")
                    .foregroundStyle(theme.secondary)
            }
            if model.currentList >= 0 || model.isWikiAllowed {
                actions
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingBackground(theme, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func header(_ target: SkyObject) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: target.type.symbol)
                .font(.title2)
                .foregroundStyle(theme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName).font(.title3.bold())
                Text(target.summary).font(.subheadline).foregroundStyle(theme.secondary)
                if let comment = model.currentWatchItem?.comment, !comment.isEmpty {
                    Text(comment).font(.subheadline).italic()
                }
                if !target.altNames.isEmpty {
                    Text(target.altNames.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(theme.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                model.clearTarget()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondary)
            .accessibilityLabel("Clear Target")
        }
    }

    private func direction(_ p: (alt: Double, az: Double, up: Double?, right: Double?)) -> some View {
        HStack(spacing: 24) {
            if let up = p.up, let right = p.right {
                Label {
                    Text("\(abs(up), format: .number.precision(.fractionLength(1)))°")
                } icon: {
                    Image(systemName: up >= 0 ? "arrow.up" : "arrow.down")
                }
                .accessibilityLabel("\(up >= 0 ? "Up" : "Down") \(abs(up), format: .number.precision(.fractionLength(1))) degrees")
                Label {
                    Text("\(abs(right), format: .number.precision(.fractionLength(1)))°")
                } icon: {
                    Image(systemName: right >= 0 ? "arrow.right" : "arrow.left")
                }
                .accessibilityLabel("\(right >= 0 ? "Right" : "Left") \(abs(right), format: .number.precision(.fractionLength(1))) degrees")
            }
        }
        .font(.title2.weight(.semibold).monospacedDigit())
        .foregroundStyle(theme.night ? Color.red : Color.green)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if model.currentList >= 0 {
                Button { model.watchListStep(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous in List")
                VStack(spacing: 0) {
                    Text(model.currentListName).font(.subheadline.weight(.semibold))
                    Text(model.watchListPosition ?? "").font(.caption).foregroundStyle(theme.secondary)
                }
                Button { model.watchListStep(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Next in List")
            }
            Spacer(minLength: 0)
            if model.isWikiAllowed {
                Button {
                    wikiURL = model.wikipediaURL
                } label: {
                    Label("Wikipedia", systemImage: "book")
                }
                .buttonStyle(.bordered)
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: Bottom bar

private struct BottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Binding var showSearch: Bool
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 0) {
            barButton(model.selectMode == .target ? "Align" : "Cancel",
                      symbol: model.selectMode == .target ? "scope" : "xmark") {
                if model.selectMode == .target { model.align() } else { model.cancelAlign() }
            }
            barButton("Search", symbol: "magnifyingglass") { showSearch = true }
            listMenu
            compassButton
            barButton("Settings", symbol: "gearshape") { showSettings = true }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .floatingBackground(theme, in: Capsule())
    }

    private func barButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accent)
    }

    private var listMenu: some View {
        Menu {
            Picker("Watch List", selection: Binding(
                get: { model.currentList },
                set: { model.selectWatchList($0) }
            )) {
                Text("None").tag(-1)
                ForEach(Array(model.watchList.names.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(i)
                }
            }
            if model.watchList.names.isEmpty {
                Text("No watch lists yet. Create them in Settings.")
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: model.currentList >= 0 ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    .font(.title3)
                Text("Lists").font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .foregroundStyle(theme.accent)
    }

    @ViewBuilder
    private var compassButton: some View {
        if !model.compassAvailable {
            VStack(spacing: 3) {
                Image(systemName: "location.slash").font(.title3)
                Text("No Compass").font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(theme.secondary)
            .accessibilityElement(children: .combine)
        } else if model.useCompass {
            barButton("Compass", symbol: "location.north.line.fill") { model.manualMode() }
                .accessibilityHint("Switches to manual mode, where you drag the map to set the azimuth")
        } else {
            barButton("Manual", symbol: "hand.draw") { model.compassMode() }
                .accessibilityHint("Switches to compass mode")
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
