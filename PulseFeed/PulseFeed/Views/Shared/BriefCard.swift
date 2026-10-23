import SwiftUI

/// Today's Brief. `.tile` = mood chip + first sentence + "N stories" (Deck tile, Stream rail);
/// `.full` = the whole digest with stories and "What to watch".
struct BriefCard: View {
    enum Mode { case tile, full }

    let digest: DailyDigest?
    var mode: Mode = .full
    var onStory: ((DigestStory) -> Void)? = nil
    var onGenerate: (() -> Void)? = nil
    /// Shown on the full card only: clears the brief and every unread story with it.
    var onClear: (() -> Void)? = nil
    @Environment(\.designTokens) private var tokens

    var body: some View {
        if let digest {
            switch mode {
            case .tile:
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "sun.max").font(.system(size: 11, weight: .bold)).foregroundStyle(tokens.accent)
                        Text("Today's Brief").font(tokens.font(11, weight: .bold)).foregroundStyle(tokens.secondaryText)
                            .lineLimit(1).fixedSize()
                        Spacer(minLength: 4)
                        if let mood = digest.marketMood { moodChip(mood).frame(maxWidth: 84) }
                    }
                    Text(Self.firstSentence(digest.summary)).font(tokens.font(12)).lineLimit(3)
                    Text("\(digest.topStories.count) stories · \(digest.isFallback ? "basic brief" : "AI")")
                        .font(tokens.font(10, weight: .semibold)).foregroundStyle(tokens.secondaryText)
                }
            case .full:
                DigestCardView(digest: digest, isCompact: false, onStoryTap: onStory, onClear: onClear)
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Generating brief…").font(tokens.font(11)).foregroundStyle(tokens.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .task { onGenerate?() }
        }
    }

    private func moodChip(_ mood: String) -> some View {
        let lower = mood.lowercased()
        let color: Color = lower.contains("bull") || lower.contains("positive") || lower.contains("risk-on") ? tokens.ok
            : lower.contains("bear") || lower.contains("negative") || lower.contains("risk-off") ? tokens.breaking
            : tokens.important
        return Text(mood)
            .font(tokens.font(10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .lineLimit(1)
    }

    static func firstSentence(_ text: String) -> String {
        if let end = text.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            return String(text[...end])
        }
        return text
    }
}
