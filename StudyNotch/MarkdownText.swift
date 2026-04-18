import SwiftUI

// ── MarkdownText ──────────────────────────────────────────────────────────────
// Renders AI responses with proper bold, bullets, headers, and highlights.
// Uses iOS/macOS AttributedString markdown support (macOS 12+).

struct MarkdownText: View {
    let raw: String

    init(_ raw: String) { self.raw = raw }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(parseBlocks(raw), id: \.id) { block in
                blockView(block)
            }
        }
    }

    // ── Block types ───────────────────────────────────────────────────────────

    enum BlockKind {
        case h1(String), h2(String), h3(String)
        case bullet(String, Int)   // text, indent level
        case numbered(String, Int, Int) // text, number, indent
        case quote(String)
        case divider
        case paragraph(String)
    }

    struct Block: Identifiable {
        let id  = UUID()
        let kind: BlockKind
    }

    // ── Parser ────────────────────────────────────────────────────────────────

    func parseBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var paraLines: [String] = []

        func flushPara() {
            let joined = paraLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(Block(kind: .paragraph(joined))) }
            paraLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushPara(); continue
            }
            // Horizontal rule
            if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") {
                flushPara(); blocks.append(Block(kind: .divider)); continue
            }
            // Headers
            if trimmed.hasPrefix("### ") {
                flushPara(); blocks.append(Block(kind: .h3(String(trimmed.dropFirst(4))))); continue
            }
            if trimmed.hasPrefix("## ") {
                flushPara(); blocks.append(Block(kind: .h2(String(trimmed.dropFirst(3))))); continue
            }
            if trimmed.hasPrefix("# ") {
                flushPara(); blocks.append(Block(kind: .h1(String(trimmed.dropFirst(2))))); continue
            }
            // Blockquote
            if trimmed.hasPrefix("> ") {
                flushPara(); blocks.append(Block(kind: .quote(String(trimmed.dropFirst(2))))); continue
            }
            // Bullets — *, -, •
            if let rest = bulletContent(line) {
                flushPara()
                let indent = bulletIndent(line)
                blocks.append(Block(kind: .bullet(rest, indent))); continue
            }
            // Numbered list
            if let (num, rest) = numberedContent(trimmed) {
                flushPara()
                blocks.append(Block(kind: .numbered(rest, num, 0))); continue
            }
            paraLines.append(trimmed)
        }
        flushPara()
        return blocks
    }

    // ── Views per block ───────────────────────────────────────────────────────

    @ViewBuilder
    func blockView(_ block: Block) -> some View {
        switch block.kind {
        case .h1(let t):
            Text(renderInline(t))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, 6)

        case .h2(let t):
            Text(renderInline(t))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, 4)

        case .h3(let t):
            Text(renderInline(t))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 2)

        case .bullet(let t, let indent):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 10)
                Text(renderInline(t))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent * 14))

        case .numbered(let t, let n, let indent):
            HStack(alignment: .top, spacing: 8) {
                Text("\(n).")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 20, alignment: .trailing)
                Text(renderInline(t))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent * 14))

        case .quote(let t):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                    .cornerRadius(2)
                Text(renderInline(t))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .divider:
            Divider().opacity(0.4)

        case .paragraph(let t):
            Text(renderInline(t))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    // ── Inline markdown → AttributedString ───────────────────────────────────

    func renderInline(_ text: String) -> AttributedString {
        // Use Swift's built-in markdown parser
        // Wrap text so it parses inline markdown (bold, italic, code, etc.)
        if let attr = try? AttributedString(markdown: text,
                                            options: AttributedString.MarkdownParsingOptions(
                                                interpretedSyntax: .inlineOnlyPreservingWhitespace
                                            )) {
            return attr
        }
        return AttributedString(text)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func bulletContent(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["* ", "- ", "• ", "+ "] {
            if t.hasPrefix(prefix) { return String(t.dropFirst(prefix.count)) }
        }
        return nil
    }

    func bulletIndent(_ line: String) -> Int {
        var count = 0
        for ch in line { if ch == " " { count += 1 } else { break } }
        return count / 2
    }

    func numberedContent(_ t: String) -> (Int, String)? {
        let pattern = #"^(\d+)\.\s+(.+)$"#
        guard let regex  = try? NSRegularExpression(pattern: pattern),
              let match  = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let numR   = Range(match.range(at: 1), in: t),
              let textR  = Range(match.range(at: 2), in: t),
              let num    = Int(t[numR])
        else { return nil }
        return (num, String(t[textR]))
    }
}
