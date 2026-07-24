import SwiftUI

enum DiaryDesign {
    static let sidebarMinimumWidth: CGFloat = 184
    static let sidebarIdealWidth: CGFloat = 210
    static let sidebarMaximumWidth: CGFloat = 250
    static let listMinimumWidth: CGFloat = 250
    static let listIdealWidth: CGFloat = 310
    static let listMaximumWidth: CGFloat = 390
    static let editorMinimumWidth: CGFloat = 360
    static let pageMaximumWidth: CGFloat = 780

    static let pageCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 7
    static let smallCornerRadius: CGFloat = 5

    static let pagePadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 24
    static let compactSpacing: CGFloat = 8
    static let animationDuration: Double = 0.2
}

extension Color {
    static var diaryAccent: Color { .pink }
    static var diaryPage: Color { .primary.opacity(0.035) }
    static var diarySecondarySurface: Color { .secondary.opacity(0.08) }
    static var diarySelection: Color { .diaryAccent.opacity(0.11) }
    static var diaryBorder: Color { .secondary.opacity(0.16) }
}

extension View {
    func diaryPageStyle() -> some View {
        self
            .background(Color.diaryPage)
            .clipShape(RoundedRectangle(cornerRadius: DiaryDesign.pageCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DiaryDesign.pageCornerRadius, style: .continuous)
                    .stroke(Color.diaryBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 12, y: 4)
    }
}
