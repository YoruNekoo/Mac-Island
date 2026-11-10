import SwiftUI

/// Square-ish icon button used across feature views. Reports interaction so auto-collapse resets.
struct IslandIconButton: View {
    let systemName: String
    let label: String
    var font: Font = IslandType.symbolControl
    var isProminent = false
    var isEnabled = true
    let action: () -> Void
    @Environment(\.islandActions) private var actions
    @Environment(\.islandAccent) private var accent

    var body: some View {
        Button {
            actions.interact()
            action()
        } label: {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(isProminent ? Color.black : IslandTheme.primaryText)
                .frame(width: 34, height: 26)
                .background(isProminent ? accent : IslandTheme.surface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

/// Plain chevron button for steppers.
struct IslandChevronButton: View {
    @Environment(\.islandPalette) private var palette
    let systemName: String
    let label: String
    let action: () -> Void
    @Environment(\.islandActions) private var actions

    var body: some View {
        Button {
            actions.interact()
            action()
        } label: {
            Image(systemName: systemName)
                .font(IslandType.captionBold)
                .foregroundStyle(palette.secondaryText)
                .frame(width: 40, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One look for every empty state and every permission message, so wording and layout never drift apart.
///
/// - Empty: a symbol, a short title, one line of detail.
/// - Permission off: "<Thing> access is off", "Turn it on in System Settings.", and an "Open Settings" button.
struct IslandNotice: View {
    @Environment(\.islandPalette) private var palette
    let symbol: String
    let title: String
    var detail: String?
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        // Kept compact so it also fits beside the recording status row.
        VStack(spacing: IslandSpacing.xxs) {
            Image(systemName: symbol)
                .font(IslandType.symbolLarge)
                .foregroundStyle(palette.secondaryText)
            Text(title)
                .font(IslandType.bodyMedium)
                .foregroundStyle(IslandTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(IslandType.caption)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            if let buttonTitle, let action {
                IslandNoticeButton(title: buttonTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "<subject> access is off" with the standard instruction and button.
    static func accessOff(symbol: String, subject: String, openSettings: @escaping () -> Void) -> IslandNotice {
        IslandNotice(symbol: symbol, title: "\(subject) access is off", detail: "Turn it on in System Settings.",
                     buttonTitle: "Open Settings", action: openSettings)
    }
}

/// The filled button used by notices: accent color, black label.
struct IslandNoticeButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.islandActions) private var actions
    @Environment(\.islandAccent) private var accent

    var body: some View {
        Button {
            actions.interact()
            action()
        } label: {
            Text(title)
                .font(IslandType.labelSemibold)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .padding(.horizontal, IslandSpacing.xxl)
                .frame(height: 22)
                .background(accent, in: RoundedRectangle(cornerRadius: IslandRadius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
