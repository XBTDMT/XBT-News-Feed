import SwiftUI

/// Idea ①: the rule between "new since you last looked" and everything older.
struct SinceDividerView: View {
    let newCount: Int
    let lastLooked: Date?
    var uppercased = true
    var onMarkRead: (() -> Void)? = nil
    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack(spacing: 8) {
            let text = SinceLastLooked.dividerText(newCount: newCount, lastLooked: lastLooked)
            Text(uppercased ? text.uppercased() : text)
                .font(tokens.font(10, weight: .bold))
                .kerning(uppercased ? 0.6 : 0)
                .foregroundStyle(tokens.accent)
                .lineLimit(1)
                .fixedSize()
            Capsule().fill(tokens.accent).frame(height: 2)
            if let onMarkRead {
                Button("Mark these read", action: onMarkRead)
                    .buttonStyle(.plain)
                    .font(tokens.font(10, weight: .bold))
                    .foregroundStyle(tokens.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tokens.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
