import SwiftUI
import AppKit
import GRDB

/// Deck floating widget as the sheet draws it: 320×200 on dark translucent grey, "Top Headlines"
/// with a plain × at the right, a 15% rule, then three rows of source line, one-line title, time.
struct DeckWidget: View {
    let appDB: AppDatabase
    @Environment(FeedEngine.self) private var engine
    @State private var articles: [ArticleInfo] = []

    private static let breakingRed = Color(hex: "#FF6961")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Top Headlines")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    NSApp.keyWindow?.orderOut(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Color.white.opacity(0.15).frame(height: 1)

            if articles.isEmpty {
                Text("No unread articles")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                        if index > 0 {
                            Color.white.opacity(0.10).frame(height: 1)
                        }
                        Button {
                            if let urlString = article.url, let url = URL(string: urlString) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if article.priority == "breaking" {
                                        Text("Breaking")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Self.breakingRed)
                                        Text("·")
                                    }
                                    Text(article.feedTitle)
                                    if article.sourceCount > 1 {
                                        Text("· \(article.sourceCount) sources")
                                    }
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                                Text(article.title ?? "Untitled")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(article.dateArrived.relativeTime)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 320, height: 200)
        .background {
            // The sheet's rgba(40,40,44,0.86): a dark tint over the blur, so the widget reads dark on
            // any desktop while still letting a little of it through.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(red: 40 / 255, green: 40 / 255, blue: 44 / 255).opacity(0.86)
            }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task { await observeHeadlines() }
    }

    private func observeHeadlines() async {
        let observation = ArticleInfo.observation(category: nil)
        do {
            for try await newArticles in observation.values(in: appDB.dbPool) {
                articles = Array(newArticles.prefix(3))
            }
        } catch {
            // Observation cancelled
        }
    }
}
