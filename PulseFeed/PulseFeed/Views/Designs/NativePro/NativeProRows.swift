import SwiftUI
import AppKit

/// The Native Pro popover row, laid out as the R1-NativePro-B sheet draws it: priority dot; a meta
/// line with source, BREAKING/IMPORTANT badge, time and the star/bookmark at its right end; a
/// two-line bold title; a two-line snippet (or the on-device summary in its place); the coverage
/// chips under the snippet; a 50pt thumbnail on the right, aligned with the title. Behaviour is
/// `HoverArticleRow`'s: tap opens, hover shows the summary/share/dismiss capsule, the context menu
/// offers Open in Browser and Copy Link, and the summary comes from `AIGate.enrichAndStore`.
struct NativeProArticleRow: View {
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
    private var isRead: Bool { article.isRead == true }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(NativeProPriority.dot(priority))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                metaLine

                Text(article.title ?? "Untitled")
                    .font(.system(size: 13.5, weight: isRead ? .semibold : .bold))
                    .foregroundStyle(isRead ? NativeProPalette.textRead : NativeProPalette.text)
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if showSummary {
                    summaryBlock
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let snippet = article.summary ?? article.contentText, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(NativeProPalette.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SourceChips(article: article, appDB: appDB)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let imageURLString = article.imageURL, let url = URL(string: imageURLString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(.top, 16)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
        .background(isHovering ? NativeProPalette.hover : Color.clear)
        .overlay(alignment: .bottomTrailing) {
            if isHovering {
                hoverCapsule
                    .padding(.trailing, 14)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }

    // MARK: - Pieces

    private var metaLine: some View {
        HStack(spacing: 6) {
            let _ = timeRefreshTick
            Text(article.feedTitle)
                .font(.system(size: 11))
                .foregroundStyle(NativeProPalette.textTertiary)
                .lineLimit(1)
            NativeProPriorityBadge(priority: priority)
            Spacer(minLength: 4)
            Text(article.dateArrived.relativeTime)
                .font(.system(size: 11))
                .foregroundStyle(NativeProPalette.textTertiary)
                .monospacedDigit()
            Button {
                print("PulseFeed: [UI] star tapped for \(article.articleID)")
                Task {
                    do { try await appDB.toggleStarred(article.articleID) }
                    catch { print("PulseFeed: [UI] Star failed: \(error)") }
                }
            } label: {
                Image(systemName: article.isStarred == true ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(article.isStarred == true ? NativeProPalette.star : NativeProPalette.iconMuted)
                    .frame(width: 13, height: 14)
            }
            .buttonStyle(.plain)
            .help(article.isStarred == true ? "Unstar" : "Star")

            Button {
                print("PulseFeed: [UI] bookmark tapped for \(article.articleID)")
                Task {
                    do { try await appDB.toggleSaved(article.articleID) }
                    catch { print("PulseFeed: [UI] Save failed: \(error)") }
                }
            } label: {
                Image(systemName: article.isSaved == true ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11))
                    .foregroundStyle(article.isSaved == true ? NativeProPalette.blue : NativeProPalette.iconMuted)
                    .frame(width: 13, height: 14)
            }
            .buttonStyle(.plain)
            .help(article.isSaved == true ? "Remove from Saved" : "Save")

            Button {
                Task { try? await appDB.dismiss(articleID: article.articleID, log: EngagementStudy.isEnabled(.standard)) }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(NativeProPalette.iconMuted)
                    .frame(width: 13, height: 14)
            }
            .buttonStyle(.plain)
            .help("Not interested")
            .accessibilityLabel("Not interested")
        }
    }

    @ViewBuilder
    private var summaryBlock: some View {
        if isLoadingSummary {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Generating summary\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(NativeProPalette.textTertiary)
            }
            .padding(.vertical, 4)
        } else if let summary, !summary.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NativeProPalette.purple)
                    .padding(.top, 2)
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(NativeProPalette.textRead)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeProPalette.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        } else {
            Text("No summary available.")
                .font(.system(size: 11))
                .foregroundStyle(NativeProPalette.textTertiary)
                .padding(.vertical, 4)
        }
    }

    /// The sheet's dark capsule: sparkles, share, close, 11pt white glyphs, 10pt apart, 9/3 padding.
    private var hoverCapsule: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSummary.toggle()
                }
                if showSummary && summary == nil {
                    Task { await loadSummary() }
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(showSummary ? Color(hex: "#D9A8F5") : Color.white)
            }
            .buttonStyle(.plain)
            .help("AI Summary")

            if let urlString = article.url, let url = URL(string: urlString) {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Share")
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(NativeProPalette.capsule, in: Capsule())
    }

    // MARK: - Summary

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

// MARK: - Priority

/// The sheet's priority colours: dot #FF3B30 / #FFCC00 / #34C759; BREAKING text #FF3B30 on 12%
/// red, IMPORTANT text #B7950B on 18% yellow.
enum NativeProPriority {
    static func dot(_ priority: String) -> Color {
        switch priority {
        case "breaking": return NativeProPalette.breaking
        case "important": return NativeProPalette.importantDot
        default: return NativeProPalette.ok
        }
    }

    static func badgeText(_ priority: String) -> Color {
        priority == "breaking" ? NativeProPalette.breaking : NativeProPalette.importantText
    }

    static func badgeFill(_ priority: String) -> Color {
        priority == "breaking" ? NativeProPalette.breaking.opacity(0.12) : NativeProPalette.importantDot.opacity(0.18)
    }
}

/// "BREAKING" / "IMPORTANT": 9pt heavy, 4/1 padding, 3pt radius. Nothing for FYI.
struct NativeProPriorityBadge: View {
    let priority: String
    var size: CGFloat = 9

    var body: some View {
        if priority == "breaking" || priority == "important" {
            Text(priority.uppercased())
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(NativeProPriority.badgeText(priority))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(NativeProPriority.badgeFill(priority), in: RoundedRectangle(cornerRadius: 3))
        }
    }
}

// MARK: - Window list row

/// The main window's list row as the sheet draws it: "Source · BREAKING" and the time on one 11pt
/// grey line, a two-line 13pt bold title (600 and #3A3A3C once read), the coverage chips; 10/12
/// padding. No dot, snippet or thumbnail; those belong to the detail pane.
struct NativeProListRow: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var timeRefreshTick: Bool = false

    private var priority: String { article.priority ?? "fyi" }
    private var isRead: Bool { article.isRead == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                let _ = timeRefreshTick
                metaText
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(article.dateArrived.relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(NativeProPalette.textTertiary)
                    .monospacedDigit()
            }
            Text(article.title ?? "Untitled")
                .font(.system(size: 13, weight: isRead ? .semibold : .bold))
                .foregroundStyle(isRead ? NativeProPalette.textRead : NativeProPalette.text)
                .lineSpacing(1.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            SourceChips(article: article, appDB: appDB)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaText: Text {
        let source = Text(article.feedTitle).foregroundStyle(NativeProPalette.textTertiary)
        guard priority == "breaking" || priority == "important" else { return source }
        return source
            + Text(" · ").foregroundStyle(NativeProPalette.textTertiary)
            + Text(priority.uppercased()).fontWeight(.bold).foregroundStyle(NativeProPriority.badgeText(priority))
    }
}
