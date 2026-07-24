import SwiftUI

struct DiarySectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

struct DiaryTagChip: View {
    let tag: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除标签 \(tag)")
            }
        }
        .font(.caption)
        .foregroundStyle(Color.diaryAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.diarySelection, in: Capsule())
    }
}

struct DiaryEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, systemImage: "square.and.pencil", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.diaryAccent)
            }
        }
    }
}

struct DiarySaveStatusView: View {
    let state: DiarySaveState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .saving:
            Label("正在保存", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .saved:
            Label("已保存", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Button(action: retry) {
                Label("保存失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("点按重试：\(message)")
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.offsets[index].x, y: bounds.minY + result.offsets[index].y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(cursor)
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            width = max(width, cursor.x - spacing)
        }

        return (offsets, CGSize(width: width, height: cursor.y + lineHeight))
    }
}
