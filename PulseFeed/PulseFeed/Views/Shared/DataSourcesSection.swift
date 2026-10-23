import SwiftUI

/// Settings › Power › Data sources (spec D10, D12, D13): which provider does each job, their credits, the
/// instruments in the strip, and the two free-key cards. Native Pro and Stream show it as a Form section;
/// Deck puts the same content in one of its cards.
struct DataSourcesContent: View {
    @State private var providers = DataProviders.stored(.standard)
    @State private var instruments = MarketInstrument.stored(.standard)
    /// Bumped when a key is added or removed, so labels and availability re-read the effective providers.
    @State private var keysVersion = 0

    private var effective: DataProviders {
        _ = keysVersion
        return providers.effective(keys: .standard)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            job("Prices", name: effective.quotes.name) {
                if QuoteSource.available.count > 1 {
                    Picker("Stock and dollar prices", selection: $providers.quotes) {
                        ForEach(QuoteSource.available, id: \.self) { Text($0.name).tag($0) }
                    }
                }
            }
            instrumentGrid
            credits
            ProviderKeyCard(key: .finnhub, onChange: { keysVersion += 1 })

            job("Live scores", name: effective.liveScores.name) {
                if LiveScoreSource.available.count > 1 {
                    Picker("NBA live scores", selection: $providers.liveScores) {
                        ForEach(LiveScoreSource.available, id: \.self) { Text($0.name).tag($0) }
                    }
                }
            }
            ProviderKeyCard(key: .balldontlie, onChange: { keysVersion += 1 })

            job("Live crypto (on power)", name: effective.cryptoStream.name) {
                if CryptoStreamSource.available.count > 1 {
                    Picker("Live coin prices", selection: $providers.cryptoStream) {
                        ForEach(CryptoStreamSource.available, id: \.self) { Text($0.name).tag($0) }
                    }
                }
            }
        }
        .onChange(of: providers) { _, p in p.store(.standard) }
        .onChange(of: instruments) { _, ids in MarketInstrument.store(ids, .standard) }
    }

    private func job<Extra: View>(_ title: String, name: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
            extra()
        }
    }

    /// Up to five; an instrument the current quote source cannot supply is shown disabled.
    private var instrumentGrid: some View {
        let quotes = effective.quotes
        return VStack(alignment: .leading, spacing: 4) {
            Text("In the strip (up to \(MarketInstrument.maxChosen))").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(MarketInstrument.all) { i in
                    let available = MarketInstrument.isAvailable(i.id, quotes: quotes)
                    let on = instruments.contains(i.id)
                    Toggle(MarketInstrument.label(i.id, quotes: quotes), isOn: Binding(
                        get: { on },
                        set: { want in
                            if want { if instruments.count < MarketInstrument.maxChosen { instruments.append(i.id) } }
                            else { instruments.removeAll { $0 == i.id } }
                        }))
                        .toggleStyle(.checkbox)
                        .disabled(!available || (!on && instruments.count >= MarketInstrument.maxChosen))
                        .help(available ? "" : "Needs a Finnhub key")
                }
            }
            if !MarketInstrument.isAvailable("oil", quotes: quotes) {
                Text("Oil needs a Finnhub key.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var credits: some View {
        let lines = DataProviders.credits(effective, instruments: instruments)
        return Group {
            if !lines.isEmpty {
                Text(lines.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// The Form section Native Pro's and Stream's Power content carries.
struct DataSourcesSection: View {
    var body: some View {
        Section("Data sources") {
            DataSourcesContent()
        }
    }
}
