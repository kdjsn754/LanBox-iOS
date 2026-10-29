import SwiftUI

/// 配色跟安卓版对齐：主色 #4263EB，卡片走系统的分组背景
enum Theme {
    static let accent = Color(red: 0.259, green: 0.388, blue: 0.922)
    static let accentSoft = Color(red: 0.259, green: 0.388, blue: 0.922).opacity(0.12)
    static let danger = Color(red: 0.851, green: 0.227, blue: 0.227)

    static let bg = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let fill = Color(.tertiarySystemFill)
    static let stroke = Color(.separator).opacity(0.6)

    static let text = Color(.label)
    static let dim = Color(.secondaryLabel)
    static let faint = Color(.tertiaryLabel)
}

extension View {
    func cardStyle(padding: CGFloat = 16, radius: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
