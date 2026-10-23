import SwiftUI
import AppKit
import WebKit

/// A list row for the window (Native Pro / Deck lists).
struct ArticleListRow: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var timeRefreshTick: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(article.feedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let priority = article.priority,
                       priority == "breaking" || priority == "important" {
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
                        .foregroundStyle(.secondary)
                }
                Text(article.title ?? "Untitled")
                    .font(.headline)
                    .fontWeight(article.isRead == true ? .regular : .bold)
                    .lineLimit(2)
                if let summary = article.summary ?? article.contentText {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                SourceChips(article: article, appDB: appDB)
            }

            if let imageURLString = article.imageURL, let url = URL(string: imageURLString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ArticleDetailView: View {
    let article: ArticleInfo
    let appDB: AppDatabase

    @State private var summary: String?
    @State private var isLoading = false
    @State private var isStarred: Bool = false
    @State private var isSaved: Bool = false
    @State private var isRead: Bool = false
    @State private var showFullArticle = false
    @State private var isReaderMode = true
    @State private var articleText = ""
    @State private var fullText: String?
    /// The learning week: which story the reader is on and since when (dwell is logged on leave).
    @State private var dwellStart: (id: String, at: Date)?
    @StateObject private var speechManager = SpeechManager()
    @AppStorage("speechRate") private var speechRate = 0.5

    var body: some View {
        VStack(spacing: 0) {
            // Summary / Full Article toggle
            if article.url != nil {
                Picker("View", selection: $showFullArticle) {
                    Text("Summary").tag(false)
                    Text("Full Article").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            if showFullArticle, let urlString = article.url, let url = URL(string: urlString) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button(isReaderMode ? "Show Original" : "Reader Mode") {
                            isReaderMode.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button {
                            if speechManager.isSpeaking {
                                speechManager.stop()
                            } else if !articleText.isEmpty {
                                speechManager.speak(articleText, rate: speechRate)
                            }
                        } label: {
                            Image(systemName: speechManager.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(speechManager.isSpeaking ? "Stop" : "Listen")
                        .disabled(articleText.isEmpty)

                        Slider(value: $speechRate, in: 0.3...0.7, step: 0.05)
                            .frame(width: 80)
                            .help("Speech rate")
                    }
                    .padding(8)

                    if isReaderMode {
                        ReaderWebView(url: url, isReaderMode: $isReaderMode, theme: AppDesign.current.readerTheme) { text in
                            articleText = text
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        WebViewWrapper(url: url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(article.title ?? "Untitled")
                            .font(.title)
                            .fontWeight(.bold)
                            .textSelection(.enabled)

                        HStack {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill((article.priority ?? "fyi").priorityColor)
                                    .frame(width: 8, height: 8)
                                Text(article.feedTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let priority = article.priority,
                               priority == "breaking" || priority == "important" {
                                Text(priority.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(priority.priorityColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(priority.priorityColor.opacity(0.15),
                                               in: RoundedRectangle(cornerRadius: 4))
                            }
                            Spacer()
                            Text(article.dateArrived.relativeTime)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Action buttons
                        HStack(spacing: 16) {
                            Button {
                                isStarred.toggle()
                                Task { try? await appDB.toggleStarred(article.articleID) }
                            } label: {
                                Label(
                                    isStarred ? "Starred" : "Star",
                                    systemImage: isStarred ? "star.fill" : "star"
                                )
                                .foregroundStyle(isStarred ? .yellow : .secondary)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                isSaved.toggle()
                                Task { try? await appDB.toggleSaved(article.articleID) }
                            } label: {
                                Label(
                                    isSaved ? "Saved" : "Save",
                                    systemImage: isSaved ? "bookmark.fill" : "bookmark"
                                )
                                .foregroundStyle(isSaved ? .blue : .secondary)
                            }
                            .buttonStyle(.bordered)

                            if !isRead {
                                Button {
                                    isRead = true
                                    Task { try? await appDB.markRead(article.articleID) }
                                } label: {
                                    Label("Mark Read", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if let imageURLString = article.imageURL, let url = URL(string: imageURLString) {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, maxHeight: 350)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }

                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.9)
                                Text("Generating AI summary...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                        } else if let summary, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.purple)
                                    Text("AI Summary")
                                        .font(.headline)
                                }
                                Text(summary)
                                    .font(.body)
                                    .lineSpacing(6)
                                    .textSelection(.enabled)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.08), Color.blue.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Divider()

                        if let content = fullText ?? article.contentText, !content.isEmpty {
                            Text(content)
                                .font(.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 12) {
                            if let urlString = article.url, let url = URL(string: urlString) {
                                Button("Open in Browser \u{2192}") {
                                    NSWorkspace.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)

                                ShareButton(url: url)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(28)
                }
            }
        }
        .onDisappear {
            speechManager.stop()
            logDwell()
        }
        .onChange(of: article.articleID) {
            speechManager.stop()
        }
        .onChange(of: speechRate) {
            if speechManager.isSpeaking {
                speechManager.speak(speechManager.currentText, rate: speechRate)
            }
        }
        .task(id: article.articleID) {
            speechManager.stop()
            logDwell()
            dwellStart = (article.articleID, Date())
            EngagementLog.shared.opened(article.articleID)
            articleText = ""
            fullText = nil
            isStarred = article.isStarred ?? false
            isSaved = article.isSaved ?? false
            isRead = article.isRead ?? false
            showFullArticle = false
            isReaderMode = true
            // ArticleInfo.contentText is a 400-char preview; the full Article record has the body.
            let text = try? await appDB.fetchArticles(ids: [article.articleID]).first?.contentText
            guard !Task.isCancelled else { return }
            fullText = text
            await loadSummary()
        }
    }

    private func logDwell() {
        guard let d = dwellStart else { return }
        EngagementLog.shared.dwell(d.id, seconds: Date().timeIntervalSince(d.at))
        dwellStart = nil
    }

    private func loadSummary() async {
        summary = nil
        isLoading = false

        if let existing = article.summary, !existing.isEmpty {
            summary = existing
            return
        }

        isLoading = true
        let result = await AIGate.shared.enrichAndStore(
            articleID: article.articleID, appDB: appDB, userInitiated: true)
        // The .task(id: article.articleID) that called us may have moved on to another article.
        guard !Task.isCancelled else { return }
        summary = result
        isLoading = false
        // Nothing to summarise with: skip the empty Summary tab and open the article itself.
        if (result ?? "").isEmpty, article.url != nil { showFullArticle = true }
    }
}
