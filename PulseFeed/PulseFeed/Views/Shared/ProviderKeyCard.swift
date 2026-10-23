import AppKit
import SwiftUI

/// One free-key upgrade, explained and offered (spec D13): what changes, that it is free and quick, a
/// sign-up button, a field with Test and save, where the key goes, and that skipping is fine. The welcome
/// flow and Settings › Power › Data sources show the same card.
struct ProviderKeyCard: View {
    let key: ProviderKey
    var store: ProviderKeyStore = .standard
    var session: URLSession = .shared
    var onChange: () -> Void = {}

    private enum Phase: Equatable { case idle, testing, failed, unreachable, saved }

    @State private var pasted = ""
    @State private var phase: Phase = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: key == .finnhub ? "chart.line.uptrend.xyaxis" : "sportscourt")
                    .foregroundStyle(.secondary)
                Text(ProviderKeyCopy.title(key)).font(.system(size: 13, weight: .semibold))
                Spacer()
                if phase == .saved {
                    Label("Added", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
            }
            Text(ProviderKeyCopy.whatChanges(key)).font(.caption).fixedSize(horizontal: false, vertical: true)
            if phase == .saved {
                Button("Remove key") {
                    store.remove(key)
                    phase = .idle
                    onChange()
                }
                .controlSize(.small)
            } else {
                Text(ProviderKeyCopy.cost(key)).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button("Get a free key") { NSWorkspace.shared.open(ProviderKeyCopy.signUpURL(key)) }
                        .controlSize(.small)
                    SecureField("Paste your key", text: $pasted)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(test)
                    if phase == .testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Test and save", action: test)
                            .controlSize(.small)
                            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if phase == .failed {
                    Text("That key didn't work. Check it and try again.").font(.caption).foregroundStyle(.red)
                } else if phase == .unreachable {
                    Text(ProviderKeyCopy.unreachable(key)).font(.caption).foregroundStyle(.orange)
                }
                Text(ProviderKeyCopy.privacy(key) + " " + ProviderKeyCopy.skip(key))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { if store.get(key) != nil { phase = .saved } }
    }

    private func test() {
        let value = pasted
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, phase != .testing else { return }
        phase = .testing
        Task {
            switch await ProviderKeyTest.run(key, value: value, session: session) {
            case .passed where (try? store.set(key, value)) != nil:
                pasted = ""
                phase = .saved
                onChange()
            case .unreachable:
                phase = .unreachable
            default:
                phase = .failed
            }
        }
    }
}
