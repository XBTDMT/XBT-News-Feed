import SwiftUI

/// "Type anything": interests typed the way a person would say them, turned into topics, follows and
/// news searches (InterestMatcher), shown as removable chips, applied on Add. Settings › Sources uses it;
/// the welcome flow's Topics and Follow steps will too.
struct InterestBox: View {
    let appDB: AppDatabase
    let catalog: Catalog
    var context: InterestContext = .topics
    var onApplied: (String) async -> Void = { _ in }
    /// The welcome flow: Add hands the chips over and applies nothing (Finish applies them).
    var onAdd: (([InterestMatch]) -> Void)? = nil

    @Environment(\.designTokens) private var tokens
    @State private var text = ""
    @State private var matches: [InterestMatch] = []
    @State private var suggestions: [InterestMatch] = []
    @State private var engine = ""
    @State private var isFinding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color(hex: "#AF52DE"))
                TextField(context == .follow ? "Type anyone you care about…" : "Type what you're into: Arsenal, sourdough, Formula E…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if !isFinding { find() } }
                Button("Find", action: find).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isFinding)
            }
            if !matches.isEmpty || !suggestions.isEmpty {
                FlowChips(matches: matches, label: label(for:)) { m in matches.removeAll { $0 == m } }
                if !suggestions.isEmpty {
                    Text("Did you mean…? Tap to add").font(.caption2).foregroundStyle(tokens.secondaryText)
                    FlowChips(matches: suggestions, label: { "+ " + label(for: $0) }, dashed: true) { m in
                        suggestions.removeAll { $0 == m }
                        if !matches.contains(m) { matches.append(m) }
                        // A followed name brings its topic, so its chip-scoped alerts have stories to fire on.
                        if case .follow(_, let topicID?) = m {
                            suggestions.removeAll { $0 == .topic(id: topicID) }
                            if !matches.contains(.topic(id: topicID)) { matches.append(.topic(id: topicID)) }
                        }
                    }
                }
                HStack {
                    Text(engine == "on-device" ? "Sorted on this Mac" : "Matched by name")
                        .font(.caption2).foregroundStyle(tokens.secondaryText)
                    Spacer()
                    Button("Add") { Task { await apply() } }.keyboardShortcut(.defaultAction)
                        .disabled(matches.isEmpty || isFinding)
                }
            }
        }
        .controlSize(.small)
    }

    private func find() {
        let typed = text
        isFinding = true
        Task {
            let r = await InterestMatcher.resolve(typed, catalog: catalog, context: context)
            matches = r.result.sure
            suggestions = r.result.suggested
            engine = r.engine
            isFinding = false
        }
    }

    private func apply() async {
        if let onAdd {
            onAdd(matches)
            matches = []
            suggestions = []
            text = ""
            return
        }
        let region = Catalog.region(for: Locale.current)
        do {
            try await appDB.applyInterests(matches, catalog: catalog, region: region)
            let n = matches.count
            matches = []
            suggestions = []
            text = ""
            await onApplied("Added \(n) \(n == 1 ? "interest" : "interests")")
        } catch {
            await onApplied("Could not add: \(error.localizedDescription)")
        }
    }

    private func label(for m: InterestMatch) -> String {
        switch m {
        case .topic(let id): return catalog.topic(id)?.label ?? id
        case .follow(let name, _): return "★ \(name)"
        case .newSearch(let phrase, _): return "🔍 \(phrase)"
        }
    }
}

/// Chips that wrap onto as many lines as they need.
private struct FlowChips: View {
    let matches: [InterestMatch]
    let label: (InterestMatch) -> String
    var dashed = false
    let remove: (InterestMatch) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(matches.enumerated()), id: \.offset) { _, m in
                Button { remove(m) } label: {
                    HStack(spacing: 3) {
                        Text(label(m))
                        if !dashed { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: "#AF52DE").opacity(0.10), in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: "#AF52DE").opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Lays its subviews out left to right, wrapping onto new lines (chips).
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
