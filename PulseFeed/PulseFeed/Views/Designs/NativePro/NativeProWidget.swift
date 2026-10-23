import SwiftUI
import AppKit
import GRDB

/// Native Pro floating widget as the sheet draws it: a 320×200 card in rgba(40,40,44,0.86) with a
/// 10pt radius; "Top Headlines" 12pt 600 with a plain close glyph; three rows of source (10pt,
/// 50% white), one-line title (12pt) and time (10pt, 40% white), ruled at 10% white.
struct NativeProWidget: View {
    let appDB: AppDatabase
    @Environment(FeedEngine.self) private var engine
    @State private var articles: [ArticleInfo] = []

    private static let card = Color(red: 40 / 255, green: 40 / 255, blue: 44 / 255).opacity(0.86)

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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)

            if articles.isEmpty {
                Text("No unread articles")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(articles) { article in
                        Button {
                            if let urlString = article.url, let url = URL(string: urlString) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(article.feedTitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .lineLimit(1)
                                Text(article.title ?? "Untitled")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(article.dateArrived.relativeTime)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if article.articleID != articles.last?.articleID {
                            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 320, height: 200)
        .background(Self.card)
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
