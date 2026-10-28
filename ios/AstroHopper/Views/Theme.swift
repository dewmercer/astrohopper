import SafariServices
import SwiftUI

/// Night mode keeps everything red on black to protect dark adaptation, so
/// controls that draw white (switches, steppers, glass) get red stand-ins.
struct Theme {
    var night: Bool

    var accent: Color { night ? .red : .accentColor }
    var primary: Color { night ? .red : .primary }
    var secondary: Color { night ? Color.red.opacity(0.7) : .secondary }
    var rowBackground: Color? { night ? Color(red: 0.09, green: 0, blue: 0) : nil }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(night: false)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies the app theme to a whole screen or sheet.
    func themed(_ theme: Theme) -> some View {
        environment(\.theme, theme)
            .tint(theme.accent)
            .foregroundStyle(theme.primary)
            .preferredColorScheme(.dark)
    }

    /// Floating control background: Liquid Glass by day, black with a red
    /// outline at night.
    @ViewBuilder
    func floatingBackground<S: Shape>(_ theme: Theme, in shape: S) -> some View {
        if theme.night {
            background(Color.black, in: shape)
                .overlay(shape.stroke(Color.red.opacity(0.6), lineWidth: 1))
        } else {
            glassEffect(.regular, in: shape)
        }
    }

    /// Black, red-tinted grouped form in night mode; standard form otherwise.
    @ViewBuilder
    func themedForm(_ theme: Theme) -> some View {
        if theme.night {
            scrollContentBackground(.hidden)
                .background(Color.black)
                .toggleStyle(NightToggleStyle())
        } else {
            self
        }
    }

    func themedRow(_ theme: Theme) -> some View {
        listRowBackground(theme.rowBackground)
    }

    /// Navigation title; system titles are always white, so at night it is
    /// drawn as a red inline title instead.
    @ViewBuilder
    func themedTitle(_ title: String, _ theme: Theme, large: Bool = false) -> some View {
        if theme.night {
            navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(title).font(.headline).foregroundStyle(Color.red)
                    }
                }
        } else {
            navigationTitle(title)
                .navigationBarTitleDisplayMode(large ? .large : .inline)
        }
    }
}

extension ToolbarContent {
    /// Hides the gray glass behind toolbar buttons at night.
    func themedBackground(_ theme: Theme) -> some ToolbarContent {
        sharedBackgroundVisibility(theme.night ? .hidden : .automatic)
    }
}

/// A switch drawn in red only.
struct NightToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .stroke(Color.red, lineWidth: 1.5)
                    .background(Capsule().fill(configuration.isOn ? Color.red.opacity(0.35) : .black))
                    .frame(width: 50, height: 30)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(Color.red).frame(width: 24, height: 24).padding(3)
                    }
                    .animation(.snappy(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A Stepper, drawn with red buttons in night mode.
struct ValueStepper: View {
    @Environment(\.theme) private var theme
    let title: String
    let value: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        if theme.night {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(theme.secondary).monospacedDigit()
                HStack(spacing: 0) {
                    Button(action: decrement) { Image(systemName: "minus").frame(width: 44, height: 30) }
                    Rectangle().fill(Color.red.opacity(0.6)).frame(width: 1, height: 18)
                    Button(action: increment) { Image(systemName: "plus").frame(width: 44, height: 30) }
                }
                .buttonStyle(.borderless)
                .overlay(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAdjustableAction { $0 == .increment ? increment() : decrement() }
        } else {
            Stepper {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value).foregroundStyle(.secondary).monospacedDigit()
                }
            } onIncrement: {
                increment()
            } onDecrement: {
                decrement()
            }
        }
    }
}

extension ObjectType {
    var displayName: String {
        switch self {
        case .star: "Star"
        case .constellation: "Constellation"
        case .openCluster: "Open Cluster"
        case .globularCluster: "Globular Cluster"
        case .galaxy: "Galaxy"
        case .nebula: "Nebula"
        case .planet: "Planet"
        case .user: "User Object"
        }
    }

    var symbol: String {
        switch self {
        case .star: "star.fill"
        case .constellation: "point.3.connected.trianglepath.dotted"
        case .openCluster: "sparkles"
        case .globularCluster: "circle.dotted.circle"
        case .galaxy: "hurricane"
        case .nebula: "cloud"
        case .planet: "circle.circle"
        case .user: "diamond"
        }
    }
}

extension SkyObject {
    var displayName: String { name ?? type.displayName }

    /// "Galaxy · m 3.4 · 2°57′"
    var summary: String {
        var parts = [name == "Moon" ? "Earth's Moon" : type.displayName]
        if mag != -1 { parts.append("m " + String(format: "%.1f", mag)) }
        if size > 0 { parts.append(Format.size(arcmin: size)) }
        return parts.joined(separator: " · ")
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
