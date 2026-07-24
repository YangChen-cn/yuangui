import SwiftUI

/// Markdown 预览（AttributedString 渲染，轻量实现）
struct DiaryMarkdownPreview: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text, let level):
                    Group {
                        switch level {
                        case 1: Text(text).font(.title).fontWeight(.bold)
                        case 2: Text(text).font(.title2).fontWeight(.bold)
                        case 3: Text(text).font(.title3).fontWeight(.semibold)
                        default: Text(text).font(.headline).fontWeight(.semibold)
                        }
                    }
                case .paragraph(let text):
                    Text(parseInline(text))
                        .font(.body)
                        .lineSpacing(4)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(parseInline(text))
                    }
                    .font(.body)
                case .code(let text):
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                case .divider:
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Block {
        case heading(String, Int)
        case paragraph(String)
        case bullet(String)
        case code(String)
        case divider
    }

    private func parseBlocks() -> [Block] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [Block] = []
        var inCode = false
        var codeBuffer: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeBuffer.joined(separator: "\n")))
                    codeBuffer = []
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuffer.append(line)
                continue
            }
            if line.hasPrefix("---") || line.hasPrefix("***") {
                blocks.append(.divider)
            } else if line.hasPrefix("# ") {
                blocks.append(.heading(String(line.dropFirst(2)), 1))
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(String(line.dropFirst(3)), 2))
            } else if line.hasPrefix("### ") {
                blocks.append(.heading(String(line.dropFirst(4)), 3))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(.paragraph(line))
            }
        }
        if inCode, !codeBuffer.isEmpty {
            blocks.append(.code(codeBuffer.joined(separator: "\n")))
        }
        return blocks
    }

    private func parseInline(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        // 粗体 **text**
        while let boldRange = result.range(of: "**") {
            guard let endRange = result[boldRange.upperBound...].range(of: "**") else { break }
            let contentRange = boldRange.upperBound..<endRange.lowerBound
            result[contentRange].font = .body.bold()
            result.removeSubrange(endRange)
            result.removeSubrange(boldRange)
        }
        // 斜体 *text*
        while let italicRange = result.range(of: "*") {
            guard let endRange = result[italicRange.upperBound...].range(of: "*") else { break }
            let contentRange = italicRange.upperBound..<endRange.lowerBound
            result[contentRange].font = .body.italic()
            result.removeSubrange(endRange)
            result.removeSubrange(italicRange)
        }
        return result
    }
}
