import SwiftUI

/// The four-page Quick Start Guide shown at startup.
struct QuickStartView: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var page = 1

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Start Guide").font(.system(size: 5.5 * pointsPerMM, weight: .bold))
                Spacer()
                Button("X") { isPresented = false }.buttonStyle(.hopperSquare)
            }
            CheckBox(title: "Don't show on startup", isOn: Binding(
                get: { !model.showTutorial }, set: { model.showTutorial = !$0 }))
            HStack {
                Button("< Prev") { page -= 1 }.buttonStyle(.hopper).disabled(page == 1).opacity(page == 1 ? 0.5 : 1)
                Button("Next >") { page += 1 }.buttonStyle(.hopper).disabled(page == 4).opacity(page == 4 ? 0.5 : 1)
            }
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 4.5 * pointsPerMM))
        .foregroundStyle(Color.ui)
        .padding()
        .background(Color.black)
        .overlay(Rectangle().stroke(Color.ui, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 1:
            page(image: "qs_1_1",
                 "Attach the phone to the optical tube so that its **top** points in the viewing direction and it lies flat on the tube.")
        case 2:
            page(image: "qs_2_1",
                 "Point the telescope to an easily identifiable star or planet **nearby** an object you want to find. For example, to find M41 or M47, point the telescope to Sirius — this is going to be the *alignment star*.",
                 "When the telescope points to the alignment star, tap **Align** and then tap the alignment star on the map. Once aligned, the app tracks the telescope movement using the phone's sensors.")
        case 3:
            page(image: nil,
                 "If you can't see the alignment star on the map, the compass may be inaccurate.",
                 "In that case tap the hand button to switch to manual mode and drag the map left or right until you see the alignment star.",
                 "Then tap **Align** and tap the alignment star on the map as usual.")
        default:
            page(image: "qs_3_1",
                 "Once aligned, tap the object you want to find (for example M41 or M47) and follow the direction line on the map until you reach the target.",
                 "It is recommended to repeat the alignment for each new target.",
                 "For detailed instructions open Settings (gear) → **?**.")
        }
    }

    private func page(image: String?, _ paragraphs: LocalizedStringKey...) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p)
            }
        }
    }
}
