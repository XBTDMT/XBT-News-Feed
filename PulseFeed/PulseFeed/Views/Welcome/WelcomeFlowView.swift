import SwiftUI

/// "Make it yours": seven screens in one window (spec §6). Back on every step after the first, Skip on the
/// skippable ones (the draft's values stand), and from Topics to Look a live preview on the right.
struct WelcomeFlowView: View {
    @Bindable var model: WelcomeFlowModel

    private var showsPreview: Bool { (WelcomeStep.topics.rawValue...WelcomeStep.look.rawValue).contains(model.step.rawValue) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    WelcomeStepView(model: model)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if showsPreview {
                    Divider()
                    WelcomePreviewPane(model: model).frame(width: 280)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 920, minHeight: 620)
        .onChange(of: model.draft.topics) { _, _ in model.refreshPreview() }
        .onChange(of: model.draft.sourceSwitches) { _, _ in model.refreshPreview() }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(WelcomeStep.allCases, id: \.self) { s in
                    Circle().fill(s == model.step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                }
            }
            if let error = model.finishError { Text(error).font(.caption).foregroundStyle(.red) }
            Spacer()
            if model.canGoBack { Button("Back") { model.back() } }
            if model.step.isSkippable { Button("Skip") { model.next() } }
            switch model.step {
            case .welcome:
                Button("Make it yours") { model.next() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case .done:
                Button(model.isFinishing ? "Saving…" : "Start reading") { model.finish() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.isFinishing)
            default:
                Button("Next") { model.next() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdvance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// Real headlines from what has been picked so far.
struct WelcomePreviewPane: View {
    let model: WelcomeFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your feed, live").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.isLoadingPreview { ProgressView().controlSize(.small) }
            }
            if model.headlines.isEmpty {
                Text(model.draft.topics.isEmpty
                     ? "Pick a topic and its newest headlines appear here."
                     : "Headlines appear here once you're online.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(model.headlines.enumerated()), id: \.offset) { _, h in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.title).font(.system(size: 12, weight: .medium)).lineLimit(3)
                                Text("\(h.source) · \(h.topicLabel)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.03))
    }
}
