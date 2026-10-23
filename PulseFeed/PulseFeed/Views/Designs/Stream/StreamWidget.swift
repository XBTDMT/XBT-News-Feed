import SwiftUI
import AppKit
import GRDB

/// Stream floating widget, 320×200: a translucent white card, "Top Headlines" in Manrope, the top
/// three unread stories as small white cards; a 4pt coral bar marks a BREAKING first row.
struct StreamWidget: View {
    let appDB: AppDatabase
    @Environment(\.designTokens) private var tokens
    @State private var articles: [ArticleInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Top Headlines")
                    .font(tokens.font(12, weight: .heavy))
                Spacer()
                Button {
                    NSApp.keyWindow?.orderOut(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StreamPalette.faint)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if articles.isEmpty {
                Text("No unread articles")
                    .font(tokens.font(11))
                    .foregroundStyle(tokens.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(articles.enumerated()), id: \.element.articleID) { index, article in
                        row(article, isLead: index == 0)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 320, height: 200, alignment: .top)
        .background(tokens.card.opacity(0.90))
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StreamPalette.scrim.opacity(0.08), lineWidth: 1))
        .task { await observeHeadlines() }
    }

    private func row(_ article: ArticleInfo, isLead: Bool) -> some View {
        let breaking = article.priority == "breaking"
        let breakingBar = isLead && breaking
        return Button {
            StreamText.open(article)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if breaking {
                        Text("BREAKING")
                            .font(tokens.font(11, weight: .heavy))
                            .foregroundStyle(tokens.breaking)
                        Text("·").font(tokens.font(11)).foregroundStyle(tokens.secondaryText)
                    }
                    Text(article.feedTitle)
                        .font(tokens.font(11, weight: breaking ? .regular : .bold))
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                    if article.sourceCount > 1 {
                        Text("· \(article.sourceCount) sources")
                            .font(tokens.font(11))
                            .foregroundStyle(tokens.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(article.dateArrived.relativeTime)
                        .font(tokens.font(11))
                        .monospacedDigit()
                        .foregroundStyle(tokens.secondaryText)
                }
                .frame(height: 14)
                Text(article.title ?? "Untitled")
                    .font(tokens.font(12, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 16)
            }
            .padding(.vertical, 7)
            .padding(.leading, breakingBar ? 12 : 10)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if breakingBar {
                    Rectangle().fill(tokens.accent).frame(width: 4)
                }
            }
            .streamCard(radius: 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
