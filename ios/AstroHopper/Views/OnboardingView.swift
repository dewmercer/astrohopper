import SwiftUI

/// Quick start, shown on first launch and from Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let image: String?
        let symbol: String
        let title: String
        let text: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(image: "qs_1_1", symbol: "iphone", title: "Attach Your Phone",
             text: "Attach the phone to the telescope tube so its **top** points where the telescope looks and it lies flat on the tube."),
        Page(image: "qs_2_1", symbol: "scope", title: "Align on a Bright Star",
             text: "Point the telescope at an easy star or planet **near** your target, such as Sirius for M41. Tap **Align**, then tap that star on the map. Center it in the eyepiece and tap **Aligned**."),
        Page(image: nil, symbol: "hand.draw", title: "Can't Find the Star?",
             text: "If the compass is off, the star may not be on screen. Tap **Compass** to switch to manual mode, drag the map until you see the star, then align as usual."),
        Page(image: "qs_3_1", symbol: "location.north.line", title: "Hop to Your Target",
             text: "Search for or tap the object you want. Move the telescope until the arrows on the card read close to zero. Align again before each new target, since the gyroscope drifts over time."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    pageView(p).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    model.showTutorial = false
                    dismiss()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(theme.night ? Color.black : Color.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(theme.night ? Color.black : nil)
        .overlay(alignment: .topTrailing) {
            Button("Skip") {
                model.showTutorial = false
                dismiss()
            }
            .padding()
        }
    }

    private func pageView(_ p: Page) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image = p.image {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .colorMultiply(theme.night ? .red : .white)
                } else {
                    Image(systemName: p.symbol)
                        .font(.system(size: 96))
                        .foregroundStyle(theme.accent)
                        .frame(height: 200)
                }
                Text(p.title).font(.title.bold()).multilineTextAlignment(.center)
                Text(p.text)
                    .font(.body)
                    .foregroundStyle(theme.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 48)
        }
    }
}
