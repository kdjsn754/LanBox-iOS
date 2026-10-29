import SwiftUI

/// 首页 / 弹层里通用的小部件

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.dim)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.faint)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct IconChip: View {
    let systemName: String
    var tint: Color = Theme.accent

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.fill.opacity(configuration.isPressed ? 0.9 : 1))
            .foregroundColor(Theme.dim)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyHint: View {
    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.faint)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.dim)
            if let detail = detail {
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 顶部导航条：和安卓版一样自己画，不用系统大标题
struct TopBar: View {
    let title: String
    var subtitle: String? = nil
    var leadingIcon: String = "chevron.left"
    var leadingAction: (() -> Void)? = nil
    var trailingIcon: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let action = leadingAction {
                Button(action: action) {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 38, height: 38)
                        .background(Theme.fill)
                        .clipShape(Circle())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.faint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let icon = trailingIcon, let action = trailingAction {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.dim)
                        .frame(width: 38, height: 38)
                        .background(Theme.fill)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
