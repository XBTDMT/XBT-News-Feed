import SwiftUI

/// The seven screens' content (copy fixed by the plan, spec §6 and D13).
struct WelcomeStepView: View {
    @Bindable var model: WelcomeFlowModel

    var body: some View {
        switch model.step {
        case .welcome: WelcomeIntro()
        case .topics: WelcomeTopicsStep(model: model)
        case .sources: WelcomeSourcesStep(model: model)
        case .follow: WelcomeFollowStep(model: model)
        case .alerts: WelcomeAlertsStep(model: model)
        case .look: WelcomeLookStep(model: model)
        case .done: WelcomeDoneStep(model: model)
        }
    }
}

private struct StepTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

/// A tappable capsule: filled when on.
struct ChoiceChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), in: Capsule())
                .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension CatalogGroup {
    var label: String {
        switch self {
        case .news: return "News"
        case .money: return "Money"
        case .techScience: return "Tech & Science"
        case .sports: return "Sports"
        case .culture: return "Culture"
        case .life: return "Life"
        }
    }
}

// MARK: - 1 Welcome

private struct WelcomeIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "newspaper").font(.system(size: 40)).foregroundStyle(Color.accentColor)
            Text("Make it yours").font(.system(size: 28, weight: .bold))
            VStack(alignment: .leading, spacing: 8) {
                Label("News Feed reads the outlets you choose.", systemImage: "dot.radiowaves.up.forward")
                Label("The same story from many outlets shows up once.", systemImage: "square.stack")
                Label("It only interrupts you for real breaking news, and everything runs on your Mac.", systemImage: "bell.badge")
            }
            .font(.system(size: 14))
            Text("About a minute. You can change everything later in Settings.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }
}

// MARK: - 2 Topics

private struct WelcomeTopicsStep: View {
    @Bindable var model: WelcomeFlowModel
    @State private var filter = ""

    var body: some View {
        let counts = model.draft.counts(catalog: model.catalog)
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "What are you into?", subtitle: "Type it the way you'd say it, start from a pack, or tick topics.")
            InterestBox(appDB: model.appDB, catalog: model.catalog, context: .topics, onAdd: { model.draft.addTyped($0) })
            let typed = model.draft.typedMatches + model.draft.follows
            if !typed.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(Array(typed.enumerated()), id: \.offset) { _, m in
                        ChoiceChip(label: label(m) + "  ✕", isOn: true) {
                            model.draft.typedMatches.removeAll { $0 == m }
                            model.draft.follows.removeAll { $0 == m }
                        }
                    }
                }
            }
            Text("Starter packs").font(.system(size: 13, weight: .semibold))
            FlowLayout(spacing: 6) {
                ForEach(WelcomePack.all) { pack in
                    let on = pack.topics.allSatisfy(model.draft.topics.contains)
                    Button { model.draft.toggle(pack: pack) } label: {
                        Label(pack.label, systemImage: pack.symbol)
                            .font(.system(size: 12, weight: on ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Topics").font(.system(size: 13, weight: .semibold))
                Spacer()
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180).controlSize(.small)
            }
            ForEach(CatalogGroup.allCases, id: \.self) { group in
                let topics = model.catalog.topics.filter { $0.group == group && matches($0) }
                if !topics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(topics) { t in
                                ChoiceChip(label: t.label, isOn: model.draft.topics.contains(t.id)) { model.draft.toggle(topic: t.id) }
                            }
                        }
                    }
                }
            }
            Text("\(counts.topics) topics · \(counts.sources) sources · \(counts.searches) news searches")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    private func matches(_ t: CatalogTopic) -> Bool {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return f.isEmpty || t.label.lowercased().contains(f) || t.aliases.contains { $0.contains(f) }
    }

    private func label(_ m: InterestMatch) -> String {
        switch m {
        case .topic(let id): return model.catalog.topic(id)?.label ?? id
        case .follow(let name, _): return "★ \(name)"
        case .newSearch(let phrase, _): return "🔍 \(phrase)"
        }
    }
}

// MARK: - 3 Sources

private struct WelcomeSourcesStep: View {
    @Bindable var model: WelcomeFlowModel
    @State private var expanded: Set<String> = []
    @State private var addingSite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Your sources", subtitle: "The outlets your topics turn on. Switch off any you don't want.")
            ForEach(model.draft.sources(catalog: model.catalog, region: model.region), id: \.topic.id) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.topic.label).font(.system(size: 13, weight: .semibold))
                    let shown = expanded.contains(group.topic.id) ? group.sources : Array(group.sources.prefix(3))
                    ForEach(shown, id: \.url) { source in
                        Toggle(source.title, isOn: Binding(
                            get: { model.draft.isOn(source) },
                            set: { model.draft.sourceSwitches[source.url] = $0 }))
                            .toggleStyle(.switch).controlSize(.small)
                    }
                    if group.sources.count > 3, !expanded.contains(group.topic.id) {
                        Button("Show all \(group.sources.count)") { expanded.insert(group.topic.id) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            }
            ForEach(model.draft.addedSites, id: \.url) { site in
                Label("\(site.title) (added)", systemImage: "plus.circle").font(.caption)
            }
            Button("+ Add a site") { addingSite = true }
        }
        .sheet(isPresented: $addingSite) {
            AddSourceSheet(appDB: model.appDB, onDone: { _ in }, onFound: { site in
                if !model.draft.addedSites.contains(site) { model.draft.addedSites.append(site) }
            })
        }
    }
}

// MARK: - 4 Follow

private struct WelcomeFollowStep: View {
    @Bindable var model: WelcomeFlowModel

    var body: some View {
        let suggested = model.draft.suggestedFollows(catalog: model.catalog)
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Who do you follow?", subtitle: "These can also break through as alerts.")
            if !suggested.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(suggested.enumerated()), id: \.offset) { _, m in
                        if case .follow(let name, _) = m {
                            ChoiceChip(label: name, isOn: model.draft.follows.contains(m)) {
                                if let i = model.draft.follows.firstIndex(of: m) { model.draft.follows.remove(at: i) } else { model.draft.follows.append(m) }
                            }
                        }
                    }
                }
            }
            InterestBox(appDB: model.appDB, catalog: model.catalog, context: .follow, onAdd: { model.draft.addTyped($0) })
            let typed = model.draft.follows.filter { !suggested.contains($0) }
            if !typed.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(Array(typed.enumerated()), id: \.offset) { _, m in
                        if case .follow(let name, _) = m {
                            ChoiceChip(label: "★ \(name)  ✕", isOn: true) { model.draft.follows.removeAll { $0 == m } }
                        }
                    }
                }
            }
            if model.draft.wantsLiveGames {
                ProviderKeyCard(key: .balldontlie)
            }
        }
    }
}

// MARK: - 5 Alerts

private struct WelcomeAlertsStep: View {
    @Bindable var model: WelcomeFlowModel
    private let intervals: [(Int, String)] = [(300, "5 min"), (900, "15 min"), (1800, "30 min"), (3600, "1 hour")]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "How should it reach you?", subtitle: "Breaking news can interrupt; everything else waits for one short recap.")
            VStack(alignment: .leading, spacing: 3) {
                Text("What can break through").font(.system(size: 12, weight: .semibold))
                ForEach(WelcomeCopy.alertKinds, id: \.self) { Text("• " + $0).font(.caption) }
            }
            ForEach(AlertMode.allCases, id: \.self) { mode in
                Button { model.draft.alertMode = mode } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.draft.alertMode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mode.label).font(.system(size: 13, weight: .semibold))
                            sampleBanner(mode)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if model.draft.alertMode != .quiet {
                Picker("Recap every", selection: $model.draft.recapInterval) {
                    ForEach(intervals, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            HStack {
                Button(model.notificationsAsked ? "Asked" : "Allow notifications") { model.askForNotifications() }
                    .disabled(model.notificationsAsked)
                Text("macOS asks once; you can change it in System Settings.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sampleBanner(_ mode: AlertMode) -> some View {
        switch mode {
        case .breakingAndRecap:
            banner("Ceasefire agreed after overnight talks", "Ceasefire · 6 sources · Northwind Wire")
        case .recapOnly:
            banner("What's new · 12 stories", "Ceasefire agreed; chip stocks slide; Lakers sign guard")
        case .quiet:
            Text("No banners. The menu bar count and the popover still show what's new.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func banner(_ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)   // as a banner shows it
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 6 Look

private struct WelcomeLookStep: View {
    @Bindable var model: WelcomeFlowModel
    @State private var keysVersion = 0

    var body: some View {
        let quotes: QuoteSource = { _ = keysVersion; return DataProviders.stored(.standard).effective(keys: .standard).quotes }()
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "How should it look?", subtitle: "Pick a design; it applies when you finish.")
            HStack(spacing: 10) {
                ForEach(AppDesign.allCases, id: \.self) { design in
                    Button { model.draft.design = design } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let thumbnail = Self.thumbnail(design) {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                                    .padding(.bottom, 4)
                            } else {
                                Image(systemName: design.glyphSymbolName).font(.system(size: 20))
                            }
                            Text(design.displayName).font(.system(size: 13, weight: .semibold))
                            Text(design.tagline).font(.caption2).foregroundStyle(.secondary).lineLimit(4)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .background(model.draft.design == design ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.draft.design == design ? Color.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("Appearance", selection: $model.draft.appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Text("Prices").font(.system(size: 13, weight: .semibold))
            Text("Up to \(MarketInstrument.maxChosen) in the strip; none hides it.").font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(MarketInstrument.all) { i in
                    let available = MarketInstrument.isAvailable(i.id, quotes: quotes)
                    ChoiceChip(label: MarketInstrument.label(i.id, quotes: quotes) + (available ? "" : " · needs a Finnhub key"),
                               isOn: model.draft.instruments.contains(i.id)) {
                        guard available else { return }
                        _ = model.draft.setInstrument(i.id, on: !model.draft.instruments.contains(i.id))
                    }
                    .opacity(available ? 1 : 0.5)
                }
            }
            let credits = DataProviders.credits(DataProviders.stored(.standard).effective(keys: .standard), instruments: model.draft.instruments)
            if !credits.isEmpty { Text(credits.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
            if model.draft.instruments.contains("bitcoin") {
                Toggle("Show BTC beside the menu bar icon", isOn: $model.draft.pricesInMenuBar)
            }
            ProviderKeyCard(key: .finnhub, onChange: { keysVersion += 1 })
        }
    }

    /// Each design's picture (`LookThumbnail`), read once; nil without one, and the card keeps its symbol.
    @MainActor private static var thumbnails: [AppDesign: NSImage?] = [:]
    @MainActor private static func thumbnail(_ design: AppDesign) -> NSImage? {
        if let cached = thumbnails[design] { return cached }
        let image = LookThumbnail.current(for: design).flatMap(NSImage.init(contentsOf:))
        thumbnails[design] = image
        return image
    }
}

// MARK: - 7 You're set

private struct WelcomeDoneStep: View {
    @Bindable var model: WelcomeFlowModel
    @State private var keysVersion = 0
    @State private var openCard: ProviderKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "You're set", subtitle: "Look for the X at the top right of your screen.")
            if !model.headlines.isEmpty {
                Text("Waiting for you").font(.system(size: 13, weight: .semibold))
                ForEach(Array(model.headlines.prefix(3).enumerated()), id: \.offset) { _, h in
                    Text("• \(h.title)").font(.system(size: 12)).lineLimit(2)
                }
            }
            Toggle("Open at login", isOn: $model.draft.openAtLogin)
            VStack(alignment: .leading, spacing: 8) {
                Text("Free upgrades").font(.system(size: 13, weight: .semibold))
                ForEach(ProviderKey.allCases, id: \.self) { key in
                    let added = { _ = keysVersion; return ProviderKeyStore.standard.get(key) != nil }()
                    HStack {
                        Text(ProviderKeyCopy.title(key)).font(.system(size: 12))
                        Text("· \(key.providerName)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if added {
                            Label("Added", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                        } else {
                            Button("Add") { openCard = key }.controlSize(.small)
                                .popover(isPresented: Binding(get: { openCard == key }, set: { if !$0 { openCard = nil } })) {
                                    ProviderKeyCard(key: key, onChange: { keysVersion += 1 }).frame(width: 380).padding(8)
                                }
                        }
                    }
                }
                Text("Both are optional; the app works without them.").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Text("Change any of this later in Settings › Sources; keys are in Settings › Power › Data sources.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
