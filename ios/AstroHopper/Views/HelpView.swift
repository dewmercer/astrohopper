import SwiftUI

/// Renders the bundled Help.md: headings, paragraphs, bullet/numbered lists and
/// indented code blocks, with inline Markdown inside each block.
struct HelpView: View {
    @Environment(\.theme) private var theme

    private enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
    }

    private let blocks: [Block] = {
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return HelpView.parse(text)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.night ? Color.black : nil)
        .themedTitle("User Guide", theme)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text)
                .font(level == 1 ? .largeTitle.bold() : level == 2 ? .title2.bold() : .headline)
                .padding(.top, level == 1 ? 0 : 12)
        case let .paragraph(text):
            inline(text)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(theme.secondary)
                inline(text)
            }
            .padding(.leading, 8)
        case let .numbered(n, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n + ".")
                inline(text)
            }
            .padding(.leading, 8)
        case let .code(text):
            Text(text)
                .font(.callout.monospaced())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.night ? Color(red: 0.09, green: 0, blue: 0) : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func inline(_ markdown: String) -> Text {
        let attributed = (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
        return Text(attributed)
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
            if !code.isEmpty {
                blocks.append(.code(code.joined(separator: "\n")))
                code = []
            }
        }

        for line in text.components(separatedBy: "\n") {
            // indented block after a blank line (list items are single lines)
            if line.hasPrefix("    ") && paragraph.isEmpty {
                code.append(String(line.dropFirst(4)))
                continue
            }
            if !code.isEmpty { flush() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if let m = trimmed.wholeMatch(of: /(#{1,6})\s+(.*)/) {
                flush()
                blocks.append(.heading(m.1.count, String(m.2)))
            } else if let m = line.wholeMatch(of: /[-*]\s+(.*)/) {
                flush()
                blocks.append(.bullet(String(m.1)))
            } else if let m = line.wholeMatch(of: /(\d+)\.\s+(.*)/) {
                flush()
                blocks.append(.numbered(String(m.1), String(m.2)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }
}
