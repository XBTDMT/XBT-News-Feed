import SwiftUI

struct DigestCardView: View {
    let digest: DailyDigest
    var isCompact: Bool = false
    var onStoryTap: ((DigestStory) -> Void)? = nil
    /// "Read it and clear it": marks everything unread read, not just the stories this card lists.
    var onClear: (() -> Void)? = nil
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.orange)
                Text("Today's Brief")
                    .font(isCompact ? .subheadline.bold() : .headline)
                Spacer()
                if let mood = digest.marketMood {
                    Text(mood)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !isCompact, let onClear {
                    Button(cleared ? "All read" : "Read it · clear all") {
                        cleared = true
                        onClear()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .foregroundStyle(cleared ? Color.secondary : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((cleared ? Color.secondary : Color.orange).opacity(0.15), in: Capsule())
                    .disabled(cleared)
                    .help("Marks every unread story read — the ones before this brief, the ones in it, and the ones that arrived behind it.")
                }
            }

            Text(digest.summary)
                .font(isCompact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(isCompact ? 3 : nil)

            if !isCompact {
                ForEach(digest.topStories) { story in
                    HStack(alignment: .top, spacing: 8) {
                        Text(categoryIcon(story.category))
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(story.headline)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(story.oneLiner)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if onStoryTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onStoryTap?(story)
                    }
                    .padding(.vertical, 2)
                }

                if !digest.whatToWatch.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What to watch")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        ForEach(Array(digest.whatToWatch.enumerated()), id: \.offset) { _, item in
                            Text("• \(item)")
                                .font(.caption)
                        }
                    }
                }
            } else {
                ForEach(digest.topStories.prefix(5)) { story in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 4, height: 4)
                        Text(story.headline)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onStoryTap?(story)
                    }
                }
            }

            Text(footerText)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(isCompact ? 10 : 16)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.08), Color.yellow.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 8 : 12))
    }

    private var footerText: String {
        let generated = digest.generatedAt.relativeTime
        return digest.isFallback
            ? "Basic brief (AI unavailable) · generated \(generated)"
            : "Generated \(generated)"
    }

    private func categoryIcon(_ category: String) -> String {
        NewsCategory.named(category).badge
    }
}
