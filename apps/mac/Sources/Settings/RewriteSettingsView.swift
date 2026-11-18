import AppKit
import SwiftUI

/// settings › ai: the one tab whose words can leave the mac, so it says so
/// at the foot. three sections: the provider (who answers, with what
/// model), which both of the others use; the rewrite (fn+⌃: whether it is
/// on, the key that asks for it, the styles); and the summaries of
/// meetings (whether they run on their own, and in what shape).
struct RewriteSettingsView: View {
    @ObservedObject var settings: RewriteSettings
    @ObservedObject var accounts: RewriteAccounts
    let dictationKey: HotkeyBinding

    @State private var pastedKey = ""
    @State private var models: [String] = []
    @State private var modelDraft = ""
    @State private var editing: RewriteStyle?
    @State private var pendingRemoval: RewriteStyle?

    /// the right-hand column every row's control sits in, so the picker,
    /// the key field and the model line up down the tab.
    private static let controlWidth: CGFloat = 230

    private var modifier: RewriteModifier {
        dictationKey.rewriteModifier(preferring: settings.modifier)
    }

    private var gesture: String {
        "\(dictationKey.displayName)+\(modifier.symbol)"
    }

    var body: some View {
        Form {
            Section {} header: {
                SectionHero(.ai)
            }

            Section("Provider") {
                providerRow
                if settings.provider.needsModelChoice {
                    modelRow
                }
            }

            Section("Dictation") {
                SettingsToggleRow(
                    "fix mistakes using what's around your cursor",
                    explanation: "after you dictate, \(settings.provider.shortName) fixes misheard names and terms using the text near your cursor. rewrites see that text too.",
                    isOn: $settings.usesCursorContext
                )
            }

            Section("Rewrite") {
                SettingsToggleRow(
                    "rewrite with \(gesture)",
                    explanation: rewriteExplanation,
                    isOn: $settings.isEnabled
                )
                keyRow
            }

            Section {
                ForEach(Array(settings.pickerStyles.enumerated()), id: \.element.id) { index, style in
                    styleRow(style, key: index + 1)
                }
                asSaidRow
            } header: {
                HStack {
                    Text("Styles")
                    Spacer()
                    Button("New Style…") {
                        editing = .custom(name: "")
                    }
                    .disabled(!settings.canAddStyle)
                }
            } footer: {
                Text("Every take gets the default. Move the pointer while you talk and the pill offers them all, each on its number key.")
            }

            Section {
                SettingsToggleRow(
                    "summarize meetings when they end",
                    explanation: summariesExplanation,
                    isOn: $settings.summariesEnabled
                )
                templateRow
            } header: {
                Text("Summaries")
            } footer: {
                privacyFootnote
            }
        }
        .settingsForm()
        .onAppear {
            accounts.refresh()
            modelDraft = settings.model(for: settings.provider)
            loadModels()
        }
        .onChange(of: settings.provider) {
            pastedKey = ""
            modelDraft = settings.model(for: settings.provider)
            loadModels()
        }
        .sheet(item: $editing) { style in
            RewriteStyleEditor(
                style: style,
                accounts: accounts,
                settings: settings,
                onSave: { saved in
                    settings.save(saved)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
        .alert(
            "Remove \(pendingRemoval?.name ?? "this style")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval {
                    settings.remove(pendingRemoval)
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// a button in a settings row: bordered when it does the thing,
    /// borderless when it is the quieter way out (sign out, cancel).
    @ViewBuilder
    private func textButton(
        _ title: String,
        quiet: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if quiet {
            Button(title.capitalizedFirst, action: action)
                .buttonStyle(.borderless)
        } else {
            Button(title.capitalizedFirst, action: action)
        }
    }

    // MARK: - the key

    /// the dictation key is set on the dictation tab; this row only adds
    /// the second key to it, and says which one is in force when the one
    /// you chose is the dictation key's own kind.
    private var keyRow: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsRowLabel(
                "rewrite key",
                explanation: modifier == settings.modifier
                    ? "held with \(dictationKey.displayName), your dictation key. that one is set on the dictation tab."
                    : "\(settings.modifier.symbol) is your dictation key's own, so \(modifier.symbol) stands in. the dictation key is set on the dictation tab."
            )
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                SettingsKeyCap(dictationKey.displayName)
                Text("+")
                    .monospaced()
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(RewriteModifier.allCases) { option in
                        Button {
                            settings.modifier = option
                        } label: {
                            if option == modifier {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName.capitalizedFirst)
                            }
                        }
                        .disabled(!option.isFree(alongside: dictationKey))
                    }
                } label: {
                    HStack(spacing: 5) {
                        SettingsKeyCap(modifier.displayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("rewrite key, held with \(dictationKey.displayName)")
            }
        }
    }

    // MARK: - who answers

    private var providerRow: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                SettingsRowLabel(
                    "who answers",
                    explanation: "\(settings.provider.setupExplanation) rewrites and meeting summaries both ask it."
                )
                Spacer(minLength: 8)
                Picker("", selection: $settings.provider) {
                    ForEach(RewriteProvider.allCases) { provider in
                        Text(provider.displayName.capitalizedFirst).tag(provider)
                    }
                }
                .labelsHidden()
                
                .frame(width: Self.controlWidth)
                .accessibilityLabel("who answers")
            }
            accountControls
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var accountControls: some View {
        let provider = settings.provider
        switch accounts.status(of: provider) {
        case let .ready(detail):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(readyLine(provider, detail: detail).capitalizedFirst)
                    
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if provider.authentication != .none {
                    Text("·")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    textButton(provider.authentication == .apiKey ? "remove key" : "sign out") {
                        accounts.signOut(provider)
                        models = []
                    }
                }
            }
        case let .working(message):
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text(message.capitalizedFirst)
                    
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                textButton("Cancel") { accounts.cancelSignIn() }
            }
        case let .unavailable(reason):
            Text(reason.capitalizedFirst)
                
                .foregroundStyle(.red)
        case let .needsSetup(problem):
            VStack(alignment: .trailing, spacing: 8) {
                if let problem {
                    Text(problem.capitalizedFirst)
                        
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
                if provider.canSignIn {
                    Button("Sign In with \(provider.signInName)…") {
                        Task {
                            await accounts.signIn(provider)
                            loadModels()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(width: Self.controlWidth, alignment: .trailing)
                }
                if provider.acceptsKey {
                    HStack(spacing: 8) {
                        SecureField(
                            provider.canSignIn ? "or paste a key" : "paste a key",
                            text: $pastedKey
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                        textButton("Save", action: saveKey)
                            .disabled(pastedKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(width: Self.controlWidth)
                }
                if let keyPage = provider.keyPage {
                    textButton("Get a Key ↗", quiet: true) {
                        NSWorkspace.shared.open(keyPage)
                    }
                }
            }
        }
    }

    /// "signed in as you@example.com", "key ending 3f9a", "ready".
    private func readyLine(_ provider: RewriteProvider, detail: String?) -> String {
        guard let detail else {
            return "ready"
        }
        return provider.authentication == .signIn ? "signed in as \(detail)" : detail
    }

    private func saveKey() {
        let key = pastedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        accounts.saveKey(key, for: settings.provider)
        pastedKey = ""
        loadModels()
    }

    // MARK: - the model

    private var modelRow: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsRowLabel(
                "model",
                explanation: "a small, fast model is plenty: a rewrite is a sentence or two, and notes are no harder. \(settings.provider.defaultModel) unless you pick another."
            )
            Spacer(minLength: 8)
            TextField(settings.provider.defaultModel, text: $modelDraft)
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .frame(width: Self.controlWidth)
                .onSubmit {
                    settings.setModel(modelDraft, for: settings.provider)
                }
                .onChange(of: modelDraft) {
                    settings.setModel(modelDraft, for: settings.provider)
                }
                .overlay(alignment: .trailing) {
                    if !models.isEmpty {
                        Menu {
                            ForEach(models, id: \.self) { model in
                                Button(model) { modelDraft = model }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 18)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .fixedSize()
                        .padding(.trailing, 4)
                        .accessibilityLabel("models \(settings.provider.displayName) offers")
                    }
                }
        }
    }

    private func loadModels() {
        let provider = settings.provider
        Task {
            let listed = await accounts.models(for: provider)
            if settings.provider == provider {
                models = listed
            }
        }
    }

    // MARK: - styles

    private func styleRow(_ style: RewriteStyle, key: Int) -> some View {
        let isDefault = style.id == settings.defaultStyleID
        return HStack(spacing: 12) {
            SettingsKeyCap("\(key)")
                .frame(width: 26)
                .accessibilityLabel("key \(key)")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(style.name)
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.tint.opacity(0.15)))
                    }
                }
                Text(summary(of: style))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            // every action in sight: the menu, and the same on right-click.
            Menu {
                styleActions(style, isDefault: isDefault)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for \(style.name)")
        }
        .contentShape(Rectangle())
        .contextMenu {
            styleActions(style, isDefault: isDefault)
        }
    }

    @ViewBuilder
    private func styleActions(_ style: RewriteStyle, isDefault: Bool) -> some View {
        Button("Make Default") {
            settings.defaultStyleID = style.id
        }
        .disabled(isDefault)
        if !style.isBuiltIn {
            Button("Edit…") { editing = style }
            Divider()
            Button("Remove…", role: .destructive) { pendingRemoval = style }
        }
    }

    /// the last button on the pill: no model at all.
    private var asSaidRow: some View {
        HStack(spacing: 12) {
            SettingsKeyCap("\(RewritePick.asSaidKey)")
                .frame(width: 26)
                .accessibilityLabel("key \(RewritePick.asSaidKey)")
            VStack(alignment: .leading, spacing: 2) {
                Text("As said")
                    
                    
                Text("On the picker only: pastes it the way you said it.")
                    
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func summary(of style: RewriteStyle) -> String {
        // the tone is the app's words, so it reads in sentence case; the
        // notes are yours and are shown as you typed them.
        let tone = (style.tone.map(\.summary)
            ?? "fits it to what you said").capitalizedFirst
        let notes = style.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.isEmpty ? tone : "\(tone) · \(notes)"
    }

    // MARK: - summaries

    /// says where the transcript goes, because this is the switch that
    /// sends other people's words somewhere.
    private var summariesExplanation: String {
        switch settings.provider {
        case .apple:
            "when a meeting is saved its transcript is read by apple's model and the notes land at the top of the file. it stays on this mac. regenerate any time from the meetings window."
        default:
            "when a meeting is saved its transcript goes to \(settings.provider.shortName) and the notes land at the top of the file. regenerate any time from the meetings window."
        }
    }

    /// an id this build doesn't know shows as auto, which is also what
    /// the summary will use for it.
    private var templateBinding: Binding<String> {
        Binding(
            get: { MeetingTemplate.resolving(settings.defaultTemplateID).id },
            set: { settings.defaultTemplateID = $0 }
        )
    }

    private var templateRow: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsRowLabel(
                "template",
                explanation: "how notes are laid out unless a meeting has its own."
            )
            Spacer(minLength: 8)
            Picker("", selection: templateBinding) {
                ForEach(MeetingTemplate.builtIn) { template in
                    Label(template.name.capitalizedFirst, systemImage: template.symbol)
                        .tag(template.id)
                }
            }
            .labelsHidden()
            
            .frame(width: Self.controlWidth)
            .accessibilityLabel("template")
        }
    }

    // MARK: - privacy

    private var privacyFootnote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(privacyLine.capitalizedFirst)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyLine: String {
        switch (settings.provider, settings.usesCursorContext) {
        case (.apple, false):
            "apple's model runs on this mac: neither a rewrite nor a summary leaves it."
        case (.apple, true):
            "apple's model runs on this mac: rewrites, fixes, summaries and the text around your cursor all stay on it."
        case (_, false):
            "a rewrite sends what you said, a summary sends what a meeting heard, and nothing else, to \(settings.provider.shortName). keys and sign-ins stay in your keychain."
        case (_, true):
            "every dictation with the text around your cursor, the app's name and your dictionary words, a rewrite and a summary are sent to \(settings.provider.shortName), and nothing else. terminals and password fields are never read. keys and sign-ins stay in your keychain."
        }
    }

    /// "never leaves this mac" holds only while the fix-up is off or local.
    private var rewriteExplanation: String {
        let staysHere = !settings.usesCursorContext || !settings.provider.needsNetwork
        return "hold \(gesture), talk, let go, and an ai rewrites it before it lands."
            + (staysHere ? " plain \(dictationKey.displayName) never leaves this mac." : "")
    }
}

/// a style of your own: a name, a place on the tone pad, figma's presets
/// to start from, a line of your own, and a try on a sentence before you
/// keep it.
struct RewriteStyleEditor: View {
    @State var style: RewriteStyle
    @ObservedObject var accounts: RewriteAccounts
    @ObservedObject var settings: RewriteSettings
    var onSave: (RewriteStyle) -> Void
    var onCancel: () -> Void

    @State private var sample = "um so i think we should probably move the sync to thursday because like half the team is out on wednesday and honestly it's not urgent"
    @State private var tried: String?
    @State private var tryFailure: String?
    @State private var isTrying = false
    @State private var tryTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(style.name.isEmpty ? "New Style" : style.name)
                .font(.title2.weight(.semibold))

            TextField("Name, as the pill shows it", text: $style.name)
                .textFieldStyle(.roundedBorder)

            HStack(alignment: .top, spacing: 18) {
                TonePadView(tone: toneBinding)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets")
                        
                    ForEach(TonePreset.all) { preset in
                        Button(preset.name) {
                            style.tone = preset.tone
                            style.notes = preset.notes
                        }
                        .buttonStyle(.borderless)
                        .fontWeight(
                            style.tone == preset.tone && style.notes == preset.notes
                                ? .semibold
                                : .regular
                        )
                    }
                    Button("Reset") {
                        style.tone = .center
                        style.notes = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    Text((style.tone ?? .center).summary)
                        .monospaced()
                        .foregroundStyle(.primary)
                        .padding(.top, 6)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Anything else")
                    
                TextField("e.g. no emoji · end with a question · write it as a commit message", text: $style.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Try it")
                        
                    Spacer()
                    if isTrying {
                        ProgressView().controlSize(.mini)
                    }
                    Button(tried == nil ? "try" : "try again", action: tryIt)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .disabled(isTrying)
                }
                TextField("something you might say", text: $sample, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                if let tried {
                    Text(tried)
                        
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tryFailure {
                    Text(tryFailure)
                        
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    tryTask?.cancel()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    tryTask?.cancel()
                    var saved = style
                    saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(style.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .tint(SystemAccent.color)
                .onDisappear { tryTask?.cancel() }
    }

    private var toneBinding: Binding<TonePosition> {
        Binding(
            get: { style.tone ?? .center },
            set: { style.tone = $0 }
        )
    }

    private func tryIt() {
        let text = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isTrying = true
        tryFailure = nil
        let style = style
        let provider = settings.provider
        let model = settings.model(for: provider)
        tryTask = Task {
            defer { isTrying = false }
            switch await accounts.connect(provider, model: model) {
            case let .failure(failure):
                tryFailure = failure.pillReason
            case let .success(connection):
                do {
                    let answer = try await connection.client.rewrite(
                        RewriteInstructions.prompt(for: text, style: style),
                        model: connection.model
                    )
                    guard !Task.isCancelled else { return }
                    tried = RewriteInstructions.cleanAnswer(answer)
                } catch let failure as RewriteFailure {
                    tryFailure = failure.pillReason
                } catch {
                    tryFailure = RewriteFailure.network.pillReason
                }
            }
        }
    }
}
