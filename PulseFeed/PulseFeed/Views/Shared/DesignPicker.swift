import SwiftUI

/// Settings › General › Design: three cards, and a "Relaunch to apply" button when the stored
/// choice differs from the running design.
struct DesignPicker: View {
    @AppStorage(AppDesign.defaultsKey) private var stored: String = AppDesign.current.rawValue
    @Environment(\.designTokens) private var tokens

    private var selected: AppDesign { AppDesign(rawValue: stored) ?? AppDesign.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 6) {
                ForEach(AppDesign.allCases, id: \.self) { design in
                    card(design)
                }
            }
            if selected != AppDesign.current {
                HStack {
                    Text("\(selected.displayName) applies after a relaunch.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Relaunch to apply") { Relauncher.relaunch() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!Relauncher.canRelaunch)
                }
                if !Relauncher.canRelaunch {
                    Text("Run from the .app bundle (make run / make install) to relaunch.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Running \(AppDesign.current.displayName).").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func card(_ design: AppDesign) -> some View {
        let isSelected = design == selected
        return Button {
            stored = design.rawValue
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: design.glyphSymbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(design.displayName).font(.system(size: 12, weight: .bold))
                        if design == AppDesign.current {
                            Text("running")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }
                    Text(design.tagline)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? tokens.accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? tokens.accent : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
