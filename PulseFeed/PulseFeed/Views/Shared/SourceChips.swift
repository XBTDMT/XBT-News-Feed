import SwiftUI
import AppKit

/// A two-to-four letter source monogram in a small dark square.
struct MonogramChip: View {
    let text: String
    var outlined = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.2)
            .foregroundStyle(Color(light: "#3A3A3C", dark: "#E5E5EA"))
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(outlined ? Color.clear : Color(light: "#E5E5EA", dark: "#3A3A3C"), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(outlined ? tokens.cardBorder : .clear, lineWidth: 1))
    }
}

/// Idea ②: "TR BBC ×3" instead of "Also in The Race F1, BBC Sport F1". Tapping opens the Coverage
/// popover. Renders nothing for single-source stories.
struct SourceChips: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    @Environment(\.designTokens) private var tokens
    @State private var showCoverage = false

    private var outlets: [String] {
        (article.otherSources ?? "").components(separatedBy: ", ").filter { !$0.isEmpty }
    }

    var body: some View {
        if article.sourceCount > 1 {
            let monos = Monogram.assign(outlets)
            Button {
                showCoverage = true
            } label: {
                HStack(spacing: 3) {
                    ForEach(Array(outlets.prefix(3)), id: \.self) { outlet in
                        MonogramChip(text: monos[outlet] ?? Monogram.make(outlet))
                    }
                    Text("×\(article.sourceCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .help("Coverage: \(article.sourceCount) sources")
            .popover(isPresented: $showCoverage, arrowEdge: .bottom) {
                CoverageList(primaryID: article.articleID, headline: article.title, appDB: appDB)
            }
        }
    }
}

/// The Coverage popover (sheet: "Coverage · 3 sources · first at 14:27", the headline, then one row per
/// outlet: monogram, name, arrival time, open arrow).
struct CoverageList: View {
    let primaryID: String
    let headline: String?
    let appDB: AppDatabase
    @Environment(\.designTokens) private var tokens
    @State private var members: [ClusterMember] = []

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Coverage").font(.system(size: 12, weight: .bold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(tokens.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 6, trailing: 12))
            Rectangle().fill(tokens.cardBorder).frame(height: 1)
            if let headline {
                Text(headline).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            }
            let monos = Monogram.assign(members.map(\.feedTitle))
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                Button {
                    if let urlString = member.url, let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: 8) {
                        MonogramChip(text: monos[member.feedTitle] ?? Monogram.make(member.feedTitle))
                        Text(member.feedTitle).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(time(member.dateArrived)).font(.system(size: 11)).monospacedDigit().foregroundStyle(tokens.secondaryText)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.accent)
                    }
                    .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < members.count - 1 { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
            }
            if members.isEmpty {
                Text("Loading…").font(.system(size: 11)).foregroundStyle(tokens.secondaryText)
                    .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            Text("Opens each outlet's own version of the story.")
                .font(.system(size: 10)).foregroundStyle(tokens.secondaryText)
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03))
        }
        .frame(width: 300)
        .task { members = (try? await appDB.fetchClusterMembers(primaryID: primaryID)) ?? [] }
    }

    private var subtitle: String {
        let n = members.count
        let first = members.map(\.dateArrived).compactMap(\.sqliteDate).min().map { Self.timeFormatter.string(from: $0) }
        return "\(n) source\(n == 1 ? "" : "s")" + (first.map { " · first at \($0)" } ?? "")
    }

    private func time(_ sqlite: String) -> String {
        sqlite.sqliteDate.map { Self.timeFormatter.string(from: $0) } ?? sqlite.relativeTime
    }
}
