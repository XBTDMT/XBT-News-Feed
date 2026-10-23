import SwiftUI
import AppKit

struct HoverArticleRow: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    let onOpen: () -> Void
    let onDismiss: () -> Void
    var timeRefreshTick: Bool = false

    @State private var isHovering = false
    @State private var showSummary = false
    @State private var summary: String?
    @State private var isLoadingSummary = false

    private var priority: String { article.priority ?? "fyi" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 8) {
                // Priority dot
                Circle()
                    .fill(priority.priorityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                // Article content — tap to open
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(article.feedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if priority == "breaking" || priority == "important" {
                            Text(priority.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(priority.priorityColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    priority.priorityColor.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        Text(article.dateArrived.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text(article.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(2)
                        .fontWeight(article.isRead == true ? .regular : .bold)

                    if !showSummary, let snippet = article.summary ?? article.contentText {
                        Text(snippet)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    SourceChips(article: article, appDB: appDB)
                        .padding(.top, 2)
                }

                // Thumbnail
                if let imageURLString = article.imageURL, let url = URL(string: imageURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            EmptyView()
                        }
                    }
                }

                // Star + Bookmark — always visible
                VStack(spacing: 4) {
                    Button {
                        print("PulseFeed: [UI] star tapped for \(article.articleID)")
                        Task {
                            do { try await appDB.toggleStarred(article.articleID) }
                            catch { print("PulseFeed: [UI] Star failed: \(error)") }
                        }
                    } label: {
                        Image(systemName: article.isStarred == true ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundStyle(article.isStarred == true ? .yellow : .secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        print("PulseFeed: [UI] bookmark tapped for \(article.articleID)")
                        Task {
                            do { try await appDB.toggleSaved(article.articleID) }
                            catch { print("PulseFeed: [UI] Save failed: \(error)") }
                        }
                    } label: {
                        Image(systemName: article.isSaved == true ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 12))
                            .foregroundStyle(article.isSaved == true ? .blue : .secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                }
                .frame(width: 28)
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Inline summary
            if showSummary {
                VStack(alignment: .leading, spacing: 8) {
                    if isLoadingSummary {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating summary...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                    } else if let summary, !summary.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.purple)
                                .padding(.top, 2)
                            Text(summary)
                                .font(.subheadline)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.06))
                    } else {
                        Text("No summary available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            if let urlString = article.url, let url = URL(string: urlString) {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(url)
                }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urlString, forType: .string)
                }
            }
        }
        .background(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        .overlay(alignment: .bottom) {
            if isHovering {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSummary.toggle()
                        }
                        if showSummary && summary == nil {
                            Task { await loadSummary() }
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(showSummary ? .purple : .white)
                    }
                    .buttonStyle(.borderless)
                    .help("AI Summary")

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")

                    if let urlString = article.url, let url = URL(string: urlString) {
                        ShareButton(url: url)
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func loadSummary() async {
        if let existing = article.summary, !existing.isEmpty {
            summary = existing
            return
        }

        isLoadingSummary = true
        summary = await AIGate.shared.enrichAndStore(
            articleID: article.articleID, appDB: appDB, userInitiated: true)
        isLoadingSummary = false
    }
}
