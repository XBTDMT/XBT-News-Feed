import SwiftUI

/// The popover's recap: the last "what's new" the app wrote, shown while there are stories since you
/// last looked. Same text as the recap notification, so the badge, the divider, the notification and
/// this card tell one story. "Mark these read" marks exactly the stories the card covers.
struct RecapCard: View {
    let summary: SummaryText
    let newCount: Int
    var onMarkRead: (() -> Void)? = nil
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.accent)
                Text("Since you last looked · \(newCount) new")
                    .font(tokens.font(11, weight: .bold))
                    .foregroundStyle(tokens.accent)
                Spacer(minLength: 4)
                if let onMarkRead {
                    Button("Mark these read", action: onMarkRead)
                        .buttonStyle(.plain)
                        .font(tokens.font(10, weight: .bold))
                        .foregroundStyle(tokens.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(tokens.accent.opacity(0.12), in: Capsule())
                }
            }
            Text(summary.body)
                .font(tokens.font(12))
                .lineSpacing(2)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: tokens.radius))
        .overlay(RoundedRectangle(cornerRadius: tokens.radius).stroke(tokens.accent.opacity(0.18), lineWidth: 1))
    }
}
