import SafariServices
import SwiftUI

/// The web app's UI is red on black everywhere to protect night vision.
extension Color {
    static let ui = Color.red
}

/// 10 mm square-ish bordered button, like the web app's `button` CSS.
struct HopperButtonStyle: ButtonStyle {
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 5 * pointsPerMM))
            .foregroundStyle(Color.ui)
            .padding(.horizontal, square ? 0 : 8)
            .frame(minWidth: 10 * pointsPerMM, minHeight: 10 * pointsPerMM)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 2 * pointsPerMM))
            .overlay(RoundedRectangle(cornerRadius: 2 * pointsPerMM).stroke(Color.ui, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == HopperButtonStyle {
    static var hopper: HopperButtonStyle { HopperButtonStyle() }
    static var hopperSquare: HopperButtonStyle { HopperButtonStyle(square: true) }
}

/// Red checkbox (a system Toggle has a bright white knob).
struct CheckBox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.square" : "square")
                Text(title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.ui)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "- +" pair followed by a value, as used for FOV, magnitude and font size.
struct IncDec: View {
    let title: String
    let value: String
    let dec: () -> Void
    let inc: () -> Void

    var body: some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            Button("-", action: dec).buttonStyle(.hopperSquare)
            Button("+", action: inc).buttonStyle(.hopperSquare)
            Text(value).italic()
            Spacer()
        }
    }
}

struct HopperTextEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 4 * pointsPerMM, design: .monospaced))
            .foregroundStyle(Color.ui)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .frame(minHeight: 120)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ui, lineWidth: 2))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
