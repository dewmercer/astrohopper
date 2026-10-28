import SwiftUI

/// Settings › Telescope: mount type, connection and goto options.
struct TelescopeSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var scope = model.telescope
        Form {
            Section {
                Toggle("Telescope Control", isOn: $scope.enabled)
            } footer: {
                Text("Slew a Celestron mount to the selected object through a SkyPortal WiFi module. The phone talks only to the module, never to the internet.")
            }
            .themedRow(theme)

            if scope.enabled {
                Section {
                    Picker("Mount", selection: $scope.mountType) {
                        ForEach(MountType.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Mount")
                } footer: {
                    Text(scope.mountType == .altAz
                         ? "For fork and single-arm mounts such as the NexStar SE, SLT, Evolution and CPC."
                         : "For mounts such as the AVX, CGEM and CGX, or a fork on a wedge. Use 2 or 3 alignment stars so AstroHopper can learn which way each axis turns.")
                }
                .themedRow(theme)

                Section {
                    Picker("Connection", selection: $scope.connectionMode) {
                        ForEach(TelescopeController.ConnectionMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(scope.state != .disconnected)
                    if scope.connectionMode == .network {
                        LabeledContent("Address") {
                            TextField("192.168.1.20", text: $scope.networkHost)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .disabled(scope.state != .disconnected)
                        }
                        Button {
                            scope.findOnNetwork()
                        } label: {
                            HStack {
                                Text("Find on Network")
                                Spacer()
                                if scope.scanning { ProgressView() }
                            }
                        }
                        .disabled(scope.scanning || scope.state != .disconnected)
                        if scope.foundHosts.count > 1 {
                            ForEach(scope.foundHosts, id: \.self) { host in
                                Button {
                                    scope.networkHost = host
                                } label: {
                                    HStack {
                                        Text(host)
                                        Spacer()
                                        if host == scope.networkHost { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        }
                    }
                    LabeledContent("Status", value: statusText)
                    switch scope.state {
                    case .disconnected:
                        Button("Connect") { scope.connect() }
                    case .connecting:
                        HStack {
                            Text("Connecting…").foregroundStyle(theme.secondary)
                            Spacer()
                            ProgressView()
                        }
                    case .connected:
                        Button("Disconnect", role: .destructive) { scope.disconnect() }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text(scope.connectionMode == .direct
                         ? "Set the module's switch to Direct Connect, join its CELESTRON WiFi network in the iPhone's Settings, then tap Connect."
                         : "Set the module's switch to Access Point and connect it to your WiFi network with Celestron's app. Then enter its address or tap Find on Network.")
                }
                .themedRow(theme)

                if let error = scope.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(theme.night ? Color.red : Color.orange)
                    }
                    .themedRow(theme)
                }

                Section {
                    LabeledContent("Mount Alignment", value: alignmentText)
                } header: {
                    Text("Alignment")
                } footer: {
                    Text("""
                    While connected, align as usual: each star you confirm with Aligned also aligns the mount. \
                    Center stars with the slew pad or the hand controller. Moving the tube by hand, or with \
                    its clutches loose, loses the mount's position.
                    """)
                }
                .themedRow(theme)

                Section {
                    Toggle("Track After GoTo", isOn: Binding(get: { scope.trackAfterGoto },
                                                             set: { scope.setTracking($0) }))
                    ValueStepper(title: "Slew Pad Speed", value: "\(scope.slewRate)",
                                 decrement: { scope.slewRate = max(1, scope.slewRate - 1) },
                                 increment: { scope.slewRate = min(9, scope.slewRate + 1) })
                } header: {
                    Text("GoTo")
                } footer: {
                    Text("""
                    The telescope stays within Settings › Altitude Limits: goto and tracking refuse objects \
                    outside them, and the slew pad stops before the maximum altitude. Before the mount is \
                    aligned, the slew pad uses the phone's altitude, so keep the phone on the tube.
                    """)
                }
                .themedRow(theme)
            }
        }
        .themedForm(theme)
        .themedTitle("Telescope", theme)
    }

    private var statusText: String {
        switch model.telescope.state {
        case .disconnected: "Not Connected"
        case .connecting: "Connecting"
        case .connected: "Connected to \(model.telescope.host)"
        }
    }

    private var alignmentText: String {
        let scope = model.telescope
        guard scope.isAligned else { return "Not Aligned" }
        let stars = scope.samples.count == 1 ? "1 star" : "\(scope.samples.count) stars"
        if let e = scope.alignmentError {
            return stars + " ±" + e.formatted(.number.precision(.fractionLength(e < 1 ? 2 : 1))) + "°"
        }
        return stars
    }
}

/// Press-and-hold arrows that move the mount, for centering stars.
struct SlewPad: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            arrow(.left, "arrow.left")
            arrow(.up, "arrow.up")
            arrow(.down, "arrow.down")
            arrow(.right, "arrow.right")
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                Button { model.telescope.slewRate = max(1, model.telescope.slewRate - 1) } label: {
                    Image(systemName: "tortoise").frame(width: 34, height: 34)
                }
                .accessibilityLabel("Slower")
                Text("\(model.telescope.slewRate)")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 16)
                    .accessibilityLabel("Speed \(model.telescope.slewRate)")
                Button { model.telescope.slewRate = min(9, model.telescope.slewRate + 1) } label: {
                    Image(systemName: "hare").frame(width: 34, height: 34)
                }
                .accessibilityLabel("Faster")
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(theme.accent)
    }

    private func arrow(_ direction: TelescopeController.Direction, _ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .frame(width: 46, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.6), lineWidth: 1.5))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 60) {
            } onPressingChanged: { pressing in
                if pressing { model.telescope.startMove(direction) } else { model.telescope.stopMove() }
            }
            .accessibilityElement()
            .accessibilityLabel("Move \(String(describing: direction))")
            .accessibilityAddTraits(.isButton)
    }
}

/// Telescope state for the status area under the alignment capsule.
struct TelescopeChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let scope = model.telescope
        Label(text, systemImage: symbol)
            .onTapGesture { scope.clearError() }
            .accessibilityHint(scope.lastError != nil ? "Tap to dismiss" : "")
    }

    private var text: String {
        let scope = model.telescope
        if let e = scope.lastError { return e }
        switch scope.state {
        case .disconnected: return "Telescope Not Connected"
        case .connecting: return "Connecting…"
        case .connected: break
        }
        switch scope.activity {
        case .slewing: return "Slewing to \(scope.targetName ?? "target")"
        case .tracking: return "Tracking \(scope.targetName ?? "target")"
        case .moving: return "Moving"
        case .idle:
            if !scope.isAligned { return "Telescope: Align to Use GoTo" }
            if let name = scope.targetName { return "At \(name), Not Tracking" }
            return "Telescope Ready"
        }
    }

    private var symbol: String {
        let scope = model.telescope
        if scope.lastError != nil { return "exclamationmark.triangle" }
        if !scope.isConnected { return "wifi.slash" }
        return scope.activity == .idle ? "dot.scope.telescope" : "scope"
    }
}
