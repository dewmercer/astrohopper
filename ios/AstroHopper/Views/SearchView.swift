import SwiftUI

/// Search for an object by name or catalog number and make it the target.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searching = true

    private var results: [Int] { model.search(query) }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Planets") {
                        ForEach(Array(model.catalog.planetIndices), id: \.self, content: row)
                    }
                    .themedRow(theme)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(results, id: \.self, content: row)
                        .themedRow(theme)
                }
            }
            .themedForm(theme)
            .themedTitle("Find Object", theme)
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "M31, NGC 7000, Vega, Jupiter…")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) {
                if let first = results.first { select(first) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                .themedBackground(theme)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let obj = model.catalog[index]
        return Button {
            select(index)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: obj.type.symbol)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(obj.displayName).foregroundStyle(theme.primary)
                    Text(([obj.summary] + obj.altNames).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if index == model.targetIndex {
                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                }
            }
        }
    }

    private func select(_ index: Int) {
        model.selectTarget(index)
        dismiss()
    }
}
