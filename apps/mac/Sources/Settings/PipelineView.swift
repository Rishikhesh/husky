import SwiftUI

/// the cleanup pipeline, as a conveyor: three stages, an arrow between each,
/// a switch on the ones that have one, and under every stage the text as
/// it leaves it — your last dictation, or a sample until there is one.
/// nothing decorative: every mark on it is a stage, a switch, or a word.
struct PipelineView: View {
    @ObservedObject private var coordinator: DictationCoordinator
    @ObservedObject private var settings: AppSettings
    @StateObject private var run: PipelinePlaygroundViewModel

    init(coordinator: DictationCoordinator, settings: AppSettings) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
        _settings = ObservedObject(wrappedValue: settings)
        let store = coordinator.dictionaryStore
        _run = StateObject(
            wrappedValue: PipelinePlaygroundViewModel(
                entries: { store.entries },
                input: coordinator.lastHeard ?? PipelineSample.text
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // the section above is titled cleanup; this only says what the
            // three columns are showing.
            Text(
                coordinator.lastHeard == nil
                    ? "A sample, until you dictate something."
                    : "Your last dictation."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 0) {
                stage("heard", lit: true) {
                    flowText(plain(heardText))
                }

                arrow

                stage("cleanup", lit: settings.cleanupEnabled) {
                    Toggle("", isOn: $settings.cleanupEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityLabel("cleanup")

                    if settings.cleanupEnabled {
                        Text("On. Spoken punctuation, emails, links, numbers, capitals.")
                            .foregroundStyle(.secondary)
                        flowText(diffText(heardText, cleanedText))
                    } else {
                        Text("Off. Only your dictionary still applies.")
                            .foregroundStyle(.secondary)
                        if cleanedText != heardText {
                            flowText(diffText(heardText, cleanedText))
                        }
                    }
                }

                arrow

                stage("pasted", lit: true) {
                    flowText(plain(finalText))
                }
            }

            // the markers are the only way to say a line break, and nothing
            // on screen named them until now. dimmed when the switch is off,
            // because then they genuinely do nothing.
            Text(PipelineSample.spokenMarkerLine.capitalizedFirst)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(settings.cleanupEnabled ? 1 : 0.6)
        }
        .onAppear {
            run.setDeterministicEnabled(settings.cleanupEnabled)
            syncOptions()
        }
        .onChange(of: settings.fuzzyDictionaryEnabled) { syncOptions() }
        .onChange(of: settings.removeFillersEnabled) { syncOptions() }
        .onChange(of: settings.speakingStyle) { syncOptions() }
        .onChange(of: settings.cleanupEnabled) { _, enabled in
            run.setDeterministicEnabled(enabled)
        }
        // the heard text, not the pasted one: the playground cleans it
        // itself, and feeding it cleaned text would show the same line twice.
        .onChange(of: coordinator.lastHeard) { _, heard in
            run.input = heard ?? PipelineSample.text
            run.recompute()
        }
    }

    private func syncOptions() {
        run.setOptions(
            fuzzyMatching: settings.fuzzyDictionaryEnabled,
            removeFillers: settings.removeFillersEnabled,
            style: settings.speakingStyle
        )
    }

    // MARK: - pieces

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 22)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    private func stage<Content: View>(
        _ title: String,
        lit: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.capitalizedFirst)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(lit ? 1 : 0.6)
    }

    // MARK: - stage text

    private var heardText: String {
        run.results.first?.output ?? run.input
    }

    private var cleanedText: String {
        run.results.first { $0.stage == .deterministic }?.output ?? heardText
    }

    private var finalText: String {
        run.results.last?.output ?? cleanedText
    }

    private func flowText(_ text: AttributedString) -> some View {
        Text(text)
            .lineLimit(6)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func plain(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        out.mergeAttributes(Self.ink(.primary))
        return out
    }

    /// gold = this stage added it, struck red = this stage took it out.
    private func diffText(_ before: String, _ after: String) -> AttributedString {
        var out = AttributedString()
        for (index, token) in WordDiff.diff(before, after).enumerated() {
            var piece = AttributedString(index == 0 ? token.text : " " + token.text)
            switch token.change {
            case .same:
                piece.mergeAttributes(Self.ink(.primary))
            case .added:
                var container = Self.ink(.primary)
                container[
                    AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self
                ] = SystemAccent.color.opacity(0.25)
                piece.mergeAttributes(container)
            case .removed:
                var container = Self.ink(Color.red.opacity(0.85))
                container[
                    AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self
                ] = .single
                piece.mergeAttributes(container)
            }
            out += piece
        }
        return out
    }

    // typed subscripts rather than key paths: the key-path spelling trips
    // a non-Sendable warning under strict concurrency.
    private static func ink(_ color: Color) -> AttributeContainer {
        var container = AttributeContainer()
        container[
            AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self
        ] = color
        return container
    }
}
