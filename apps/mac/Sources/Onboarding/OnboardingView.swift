import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import SwiftUI
import ThinkingOrbsKit

@MainActor
private final class OnboardingWindowResizer {
    weak var window: NSWindow?

    func resize(to contentHeight: CGFloat, animated: Bool) {
        // Window mutations are deferred past the SwiftUI graph update that
        // requested them, matching the HUD/AttributeGraph safety rule.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else {
                return
            }

            let currentFrame = window.frame
            let targetFrameSize = window.frameRect(
                forContentRect: NSRect(
                    origin: .zero,
                    size: NSSize(
                        width: OnboardingView.windowWidth,
                        height: contentHeight
                    )
                )
            ).size
            guard abs(currentFrame.height - targetFrameSize.height) > 0.5
            else {
                return
            }

            let targetFrame = NSRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - targetFrameSize.height,
                width: targetFrameSize.width,
                height: targetFrameSize.height
            )
            window.setFrame(
                targetFrame,
                display: true,
                animate: animated
                    && !NSWorkspace.shared
                        .accessibilityDisplayShouldReduceMotion
            )
        }
    }
}

@MainActor
final class OnboardingWindowController:
    NSWindowController,
    NSWindowDelegate
{
    /// which jobs this window was built for; a different ask needs a
    /// different window.
    let scope: OnboardingScope
    /// which screen it opens on. the flow lives inside the view, so a window
    /// built for one errand cannot be reopened on another.
    let openAt: OnboardingStep

    private weak var coordinator: DictationCoordinator?

    /// `scope` and the two meeting closures are the whole seam: the coordinator
    /// says which errand this window is for and hands it the real probe and the
    /// real download when they exist. Defaults keep every existing call site —
    /// and the stubs — working unchanged.
    init(
        coordinator: DictationCoordinator,
        scope: OnboardingScope = .everything,
        openAt: OnboardingStep = .hello,
        proveSystemAudio: @escaping OnboardingMeetingSetup.SystemAudioProof =
            OnboardingMeetingSetup.stubbedSystemAudioProof,
        prepareMeetingModel:
            @escaping OnboardingMeetingSetup.MeetingModelPreparation =
                OnboardingMeetingSetup.stubbedMeetingModelPreparation
    ) {
        self.coordinator = coordinator
        self.scope = scope
        self.openAt = openAt

        // the folder the transcripts go in, made during setup so macOS asks
        // for ~/Documents here rather than mid-save at the end of the first
        // meeting. `folderName` is MeetingTranscriptFile's, so the path stays
        // defined once.
        let transcriptsFolder = coordinator.settings.meetingsFolder
            .appendingPathComponent(
                MeetingTranscriptFile.folderName,
                isDirectory: true
            )

        let resizer = OnboardingWindowResizer()
        let rootView = OnboardingView(
            coordinator: coordinator,
            scope: scope,
            openAt: openAt,
            meetingSetup: OnboardingMeetingSetup(
                proveSystemAudio: proveSystemAudio,
                prepareMeetingModel: prepareMeetingModel,
                prepareMeetingsFolder: {
                    OnboardingMeetingSetup.createFolder(at: transcriptsFolder)
                }
            ),
            windowResizer: resizer
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        resizer.window = window
        window.title = "Husky"
        // a setup assistant's window: no title, the glass running up under
        // the traffic lights.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(
            NSSize(
                width: OnboardingView.windowWidth,
                height: OnboardingView.windowHeight
            )
        )
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.onboardingWindowDidClose(self)
    }
}

@MainActor
private final class OnboardingPermissionModel: ObservableObject {
    @Published private(set) var microphoneStatus: AVAuthorizationStatus
    @Published private(set) var accessibilityGranted: Bool

    private var accessibilityPromptTriggered = false

    init() {
        microphoneStatus =
            AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityGranted = AXIsProcessTrusted()
    }

    func refresh() {
        microphoneStatus =
            AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestMicrophoneAccess(
        requestAccess: @escaping @MainActor () async -> Bool
    ) {
        Task { @MainActor [weak self] in
            _ = await requestAccess()
            self?.microphoneStatus =
                AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    func requestAccessibilityPrompt() {
        guard !accessibilityPromptTriggered else {
            return
        }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:
                true
        ] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        accessibilityPromptTriggered = true
    }

    func openMicrophoneSettings() {
        openPrivacySettings(
            "com.apple.preference.security?Privacy_Microphone"
        )
    }

    func openAccessibilitySettings() {
        openPrivacySettings(
            "com.apple.preference.security?Privacy_Accessibility"
        )
    }

    private func openPrivacySettings(_ path: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:" + path
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// What the key test has to say, in one value.
///
/// `pickerShown` is sticky on purpose: once setup has offered another key,
/// withdrawing the offer the moment it is taken would read as a glitch. One
/// state change on the first bump, and no staged "let go" beat — detection-only
/// mode returns early on release, so a second beat would be a timer pretending
/// to watch the user.
private struct KeyTest: Equatable {
    var fired = false
    var patienceSpent = false
    var pickerShown = false
    /// changing this re-arms the wait, which is how a freshly picked key gets
    /// its own six seconds.
    var armedAt = Date()

    mutating func markFired() {
        fired = true
    }

    mutating func spendPatience() {
        patienceSpent = true
        pickerShown = true
    }

    mutating func rearm() {
        fired = false
        patienceSpent = false
        armedAt = Date()
    }

    func caption(for binding: HotkeyBinding) -> String {
        if fired {
            return "Got it. That key works on this keyboard."
        }
        guard patienceSpent else {
            return "Press and hold it."
        }
        // the fn sentence is only true about fn: someone who rebound in
        // settings and reran setup would be told a lie.
        return binding == .fn
            ? "Nothing yet. fn only exists on Apple keyboards. Try another."
            : "Nothing yet. Try another key."
    }
}

struct OnboardingView: View {
    // Every screen is the same size. The window used to grow from 430 to 648
    // when setup began, moving itself under the pointer at the exact moment
    // the user was reaching for something.
    fileprivate static let windowWidth: CGFloat = 540
    fileprivate static let windowHeight: CGFloat = 600

    /// How long setup waits for the key before offering another one. A
    /// provisional number, like the dead-tap window: long enough that nobody
    /// is accused of not trying, short enough to still be on this screen.
    private static let keyTestPatience: TimeInterval = 6

    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var coordinator: DictationCoordinator
    @ObservedObject private var settings: AppSettings
    @StateObject private var permissions: OnboardingPermissionModel
    @StateObject private var meetingSetup: OnboardingMeetingSetup
    @State private var onboarding: OnboardingState
    @State private var flow: OnboardingFlow
    @State private var keyTest = KeyTest()
    @StateObject private var loginItem = LoginItemController()
    /// the coda row's tick. seeded from macOS's answer on appear, applied
    /// only by the last button.
    @State private var launchAtLogin = true
    /// which way the last step change went, so the next screen slides in
    /// from the side it lives on.
    @State private var movingForward = true

    private let windowResizer: OnboardingWindowResizer
    /// `.hello` unless something went wrong and this window was reopened to
    /// fix it. opening straight at a later screen means the consent that
    /// screen assumes has to be given here instead.
    private let openAt: OnboardingStep

    fileprivate init(
        coordinator: DictationCoordinator,
        scope: OnboardingScope,
        openAt: OnboardingStep = .hello,
        meetingSetup: OnboardingMeetingSetup,
        windowResizer: OnboardingWindowResizer
    ) {
        let permissions = OnboardingPermissionModel()
        var onboarding = OnboardingState(scope: scope)
        if scope == .permissionsOnly {
            // there is nothing here to consent to — the jobs were picked
            // weeks ago and the models are on disk. Consenting is what makes
            // the row read "open settings" instead of offering an "allow"
            // macOS ignores for an app it already lists.
            onboarding.consentToSetup()
        }
        onboarding.updateMicrophoneStatus(
            Self.microphoneRowStatus(for: permissions.microphoneStatus)
        )
        onboarding.updateAccessibility(
            granted: permissions.accessibilityGranted
        )
        onboarding.updateModelStatus(
            Self.modelRowStatus(for: coordinator.enginePreparationState)
        )

        _coordinator = ObservedObject(wrappedValue: coordinator)
        _settings = ObservedObject(wrappedValue: coordinator.settings)
        _permissions = StateObject(wrappedValue: permissions)
        _meetingSetup = StateObject(wrappedValue: meetingSetup)
        _onboarding = State(initialValue: onboarding)
        // built here rather than jumped to in onAppear, so the hello screen
        // never flashes for a frame on the way to the broken row. a
        // permissions-only reopen always starts on that row; any other
        // reopen starts where the errand said.
        let startingStep: OnboardingStep =
            scope == .permissionsOnly ? .permissions : openAt
        _flow = State(initialValue: OnboardingFlow(step: startingStep))
        self.openAt = startingStep
        self.windowResizer = windowResizer
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                stepBody
                    .id(flow.step)
                    .transition(stepTransition)
                    .padding(.horizontal, 44)
                    .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)

            navigation
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .padding(.top, 10)
        }
        // under the traffic lights: the title bar is see-through.
        .padding(.top, 34)
        .frame(width: Self.windowWidth, height: Self.windowHeight)
        .glassWindow(glow: glowTint)
        .ignoresSafeArea()
        .onAppear {
            permissions.refresh()
            // Skipping past `hello` skips the click that gives consent and
            // starts the probe. Without it the system audio row would read
            // "proved when you click" — a window opened to fix a failure,
            // showing neither the failure nor its button.
            if openAt != .hello {
                onboarding.consentToSetup()
                if onboarding.meetingsSelected {
                    meetingSetup.begin()
                }
            }
            synchronizeOnboarding()
            // read from macOS rather than assumed: setup reopened from
            // `record a meeting` should show the real state, not re-ask.
            loginItem.refresh()
            launchAtLogin = loginItem.isEnabled || loginItem.isUnregistered
            windowResizer.resize(to: Self.windowHeight, animated: false)
        }
        .onChange(of: permissions.microphoneStatus) { _, _ in
            synchronizePermissions()
        }
        .onChange(of: permissions.accessibilityGranted) { _, _ in
            synchronizePermissions()
        }
        .onChange(of: coordinator.enginePreparationState) { _, _ in
            synchronizeEngine()
        }
        // the press itself, published on every bump of the bound key. the
        // window is key while setup is on screen, so the local monitor
        // delivers it without accessibility being granted yet.
        .onChange(of: coordinator.hotkeyDetection) { _, detection in
            guard detection != nil else {
                return
            }
            keyTest.markFired()
        }
        .onChange(of: meetingSetup.systemAudioStatus) { _, _ in
            synchronizeMeetings()
        }
        .onChange(of: meetingSetup.modelStatus) { _, _ in
            synchronizeMeetings()
        }
        // Coming back from privacy settings is the one moment re-proving is
        // worth a sound: the switch you just flipped is the only thing that
        // could have changed the answer.
        .onChange(of: controlActiveState) { _, state in
            if state == .key {
                meetingSetup.proveSystemAudioAgain()
            }
        }
        // The permission rows are read from the system every second, so a
        // grant made in System Settings shows up here without the user having
        // to come back and prod anything.
        .task {
            permissions.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
                permissions.refresh()
            }
        }
    }

    // MARK: - motion and colour

    /// a short slide from the side the screen lives on, and a fade; with
    /// Reduce Motion, only the fade.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }
        let shift: CGFloat = movingForward ? 28 : -28
        return .asymmetric(
            insertion: .offset(x: shift).combined(with: .opacity),
            // the outgoing screen only fades: its transition was fixed
            // when it last drew, before anyone knew which way this goes.
            removal: .opacity
        )
    }

    /// every step change goes through here, so the slide knows its direction
    /// and runs on one curve.
    private func move(_ change: (inout OnboardingFlow) -> Void) {
        var next = flow
        change(&next)
        guard next.step != flow.step else {
            return
        }
        movingForward = next.step.rawValue > flow.step.rawValue
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)) {
            flow = next
        }
    }

    /// the glow at the window's foot takes the step's colour, and green when
    /// setup is done.
    private var glowTint: Color {
        switch flow.step {
        case .hello:
            AppLook.accent
        case .model:
            .indigo
        case .permissions:
            onboarding.verdict == .ready ? .green : .blue
        }
    }

    // MARK: - the screens

    private var stepTitle: String {
        flow.step.title(for: onboarding.jobs, verdict: onboarding.verdict)
            .onboardingCase
    }

    private var stepReason: String {
        flow.step.reason(
            for: onboarding.jobs,
            key: settings.dictationHotkey.displayName,
            verdict: onboarding.verdict
        )
        .onboardingCase
    }

    @ViewBuilder
    private var stepBody: some View {
        VStack(spacing: 18) {
            switch flow.step {
            case .hello:
                helloHero
                jobRows
            case .model:
                SectionHero(
                    symbol: "cpu",
                    tint: .indigo,
                    title: stepTitle,
                    blurb: stepReason
                )
                modelProgress
                keyTestBlock
            case .permissions:
                if onboarding.verdict == .ready {
                    SectionHero(
                        symbol: "checkmark",
                        tint: .green,
                        title: stepTitle,
                        blurb: stepReason
                    )
                    readyPanel
                } else {
                    SectionHero(
                        symbol: "hand.raised.fill",
                        tint: .blue,
                        title: stepTitle,
                        blurb: stepReason
                    )
                    permissionRows
                }

                // its own module below the checklist, because it is a coda
                // and not a fourth permission.
                if loginItem.isAvailable {
                    launchAtLoginRow
                }
            }
        }
        .frame(maxWidth: .infinity)
        // the last card turning from checklist to arrival, eased.
        .animation(.easeOut(duration: 0.25), value: onboarding.verdict)
    }

    /// the welcome: the user's own listening orb, live, where the other
    /// screens have an icon. reopened for one meeting errand, the errand's
    /// icon instead — this is not an introduction.
    private var helloHero: some View {
        VStack(spacing: 6) {
            Group {
                if onboarding.scope == .meetingsOnly {
                    IconTile(symbol: "person.2.fill", tint: .orange, size: 60)
                } else {
                    ThinkingOrb(
                        state: OrbState(rawValue: settings.listeningOrb.rawValue)
                            ?? .composing,
                        theme: .auto,
                        displaySize: 64
                    )
                    .padding(14)
                    .glassEffect(.regular, in: Circle())
                    .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 8)

            Text(stepTitle)
                .font(.largeTitle.weight(.bold))

            if onboarding.scope == .everything {
                Text("Escape the keyboard.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(stepReason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    /// Two jobs, both priced; dictation on, meetings offered. Ticking or
    /// unticking one adds or takes its rows and its download — the fork is
    /// here and nowhere else (ADR 0040).
    /// In `meetingsOnly` there is nothing to choose: pressing `record a
    /// meeting` was the choice.
    @ViewBuilder
    private var jobRows: some View {
        if onboarding.scope == .everything {
            SetupModule {
                SetupRow(
                    symbol: "waveform",
                    tint: .blue,
                    title: "Dictation",
                    detail: "\(OnboardingJobs.dictationDownload) download"
                        .onboardingCase
                ) {
                    switchControl(
                        "Dictation",
                        isOn: Binding(
                            get: { onboarding.dictationSelected },
                            set: { onboarding.setDictationSelected($0) }
                        )
                    )
                }

                SetupDivider()

                SetupRow(
                    symbol: "person.2.fill",
                    tint: .orange,
                    title: "Meeting recording",
                    detail: "\(OnboardingJobs.meetingsDownload) download"
                        .onboardingCase
                ) {
                    switchControl(
                        "Meeting recording",
                        isOn: Binding(
                            get: { onboarding.meetingsSelected },
                            set: { onboarding.setMeetingsSelected($0) }
                        )
                    )
                }
            }
        }
    }

    private func switchControl(
        _ label: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(label, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    /// `LSUIElement` is true: no dock icon, no window, so after a restart the
    /// app is simply not running and the only symptom is the key doing
    /// nothing — which feels exactly like a revoked permission. Ticked by
    /// default, registered by the last button and by nothing else: closing
    /// this window still records nothing (ADR 0029).
    private var launchAtLoginRow: some View {
        SetupModule {
            SetupRow(
                symbol: "power",
                tint: .gray,
                title: "Start Husky when you sign in",
                detail: loginItem.message?.onboardingCase
                    ?? "Otherwise it isn't running after a restart."
            ) {
                switchControl("Start Husky when you sign in", isOn: $launchAtLogin)
            }
        }
    }

    /// One row per ticked job, named for its job only when there are two of
    /// them — a lone download does not need to say which job it is for.
    private var modelProgress: some View {
        let bothJobs =
            onboarding.dictationSelected && onboarding.meetingsSelected

        return SetupModule {
            if onboarding.dictationSelected {
                dictationModelRow(title: bothJobs ? "Dictation" : "Speech model")
            }
            if bothJobs {
                SetupDivider()
            }
            if onboarding.meetingsSelected {
                meetingModelProgressRow(title: bothJobs ? "Meetings" : "Speech model")
            }
        }
    }

    private var dictationDownloadNote: String {
        "about \(coordinator.settings.dictationModel.approximateSize.dropFirst()). carry on — this keeps going."
            .onboardingCase
    }

    private var meetingDownloadNote: String {
        "about \(coordinator.settings.meetingModel.approximateSize.dropFirst()). carry on — this keeps going."
            .onboardingCase
    }

    /// The download does not gate anything. It starts when the user says go and
    /// keeps running while they carry on — blocking the flow on ~460 MB was the
    /// thing that made setup feel long.
    @ViewBuilder
    private func dictationModelRow(title: String) -> some View {
        switch coordinator.enginePreparationState {
        case let .downloading(progress):
            // nothing is coming down when it is already here, so no bar and
            // no size: a quoted 460 mb that never gets fetched is the same
            // lie as the caption below, one beat earlier.
            if coordinator.engineModelWasOnDisk {
                SetupRow(symbol: "waveform", tint: .blue, title: title, detail: "Warming up…") {
                    ProgressView().controlSize(.small)
                }
            } else {
                SetupRow(symbol: "waveform", tint: .blue, title: title, detail: dictationDownloadNote) {
                    progressBar(progress)
                }
            }
        case .warmingUp:
            SetupRow(symbol: "waveform", tint: .blue, title: title, detail: "Warming up…") {
                ProgressView().controlSize(.small)
            }
        case .ready:
            // Two different things end here: a real download, and a folder
            // another install or another app had already filled. One line for
            // both told whoever watched the bar fill that nothing came down.
            SetupRow(
                symbol: "waveform",
                tint: .blue,
                title: title,
                detail: OnboardingState.modelReadyCaption(
                    wasOnDisk: coordinator.engineModelWasOnDisk
                ).onboardingCase
            ) {
                StatusDone(text: "Ready")
            }
        case .failed:
            SetupRow(
                symbol: "waveform",
                tint: .blue,
                title: title,
                detail: "That download didn't finish.",
                detailIsAlert: true
            ) {
                Button("Try Again") { coordinator.retryEnginePrewarm() }
                    .buttonStyle(.glassProminent)
            }
        case .notStarted:
            SetupRow(symbol: "waveform", tint: .blue, title: title, detail: "Starting…") {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var meetingModelReadyCaption: String {
        switch coordinator.settings.meetingModel {
        case .whisperLargeV3: "Got it. It hears every language and writes English."
        case .whisperLargeV3Turbo: "Got it. It hears every language and writes it as spoken."
        case .parakeetUltra, .parakeetV3: "Got it. It hears English and European languages, as spoken."
        case .parakeetV2: "Got it. It hears English, as spoken."
        case .whistle: "Got it. It hears English and six European languages, as spoken."
        }
    }

    /// The same idiom as the dictation model, one job over: it starts on the
    /// click, it says what it costs, and a failure offers the retry rather
    /// than leaving a dead row.
    @ViewBuilder
    private func meetingModelProgressRow(title: String) -> some View {
        switch meetingSetup.modelStatus {
        case .pending:
            SetupRow(symbol: "person.2.fill", tint: .orange, title: title, detail: "Starts when you click.") {
                EmptyView()
            }
        case .inProgress:
            SetupRow(symbol: "person.2.fill", tint: .orange, title: title, detail: meetingDownloadNote) {
                progressBar(meetingSetup.modelProgress)
            }
        case .ready:
            // one decode for the whole room, so the language is the model's
            // choice: turbo cannot translate, and saying it writes english
            // would be a promise it does not keep. nor does parakeet hear
            // every language — setup only gets here with it if it was
            // picked in settings first.
            SetupRow(symbol: "person.2.fill", tint: .orange, title: title, detail: meetingModelReadyCaption) {
                StatusDone(text: "Ready")
            }
        case .actionRequired:
            SetupRow(
                symbol: "person.2.fill",
                tint: .orange,
                title: title,
                detail: "That download didn't finish.",
                detailIsAlert: true
            ) {
                Button("Try Again") { meetingSetup.retryModel() }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        ProgressView(value: bounded(progress))
            .progressViewStyle(.linear)
            .frame(width: 110)
    }

    /// Proof, not configuration. The key is the one part of dictation setup
    /// cannot verify for you — fn does not exist on a Keychron, and the app
    /// would otherwise say nothing about it ever again. So the press happens
    /// here, while there is still a screen to answer on, and the picker
    /// appears only after the shipped default has visibly failed to fire.
    ///
    /// A meetings-only setup has no key to prove, and before consent there is
    /// nothing to prove it for.
    @ViewBuilder
    private var keyTestBlock: some View {
        if onboarding.consented, onboarding.dictationSelected {
            SetupModule {
                SetupRow(
                    symbol: "keyboard",
                    tint: keyTest.fired ? .green : .gray,
                    title: "Your key",
                    detail: keyTest.caption(for: settings.dictationHotkey),
                    detailIsSuccess: keyTest.fired
                ) {
                    if keyTest.pickerShown {
                        keyPicker
                    } else {
                        keyCap
                    }
                }
                // the tallest state's height from the first render: the
                // picker must not push the card around under the pointer.
                .frame(minHeight: 52)
            }
            .task(id: keyTest.armedAt) {
                do {
                    try await Task.sleep(for: .seconds(Self.keyTestPatience))
                } catch {
                    return
                }
                guard !keyTest.fired else {
                    return
                }
                keyTest.spendPatience()
            }
        }
    }

    /// the key lights in the accent the moment it is heard.
    private var keyCap: some View {
        SettingsKeyCap(
            settings.dictationHotkey.displayName,
            isActive: keyTest.fired
        )
        .scaleEffect(keyTest.fired && !reduceMotion ? 1.08 : 1)
        .animation(.easeOut(duration: 0.16), value: keyTest.fired)
    }

    /// The same menu settings owns (one key picker in the app, rendered
    /// twice), so a pick here is the real rebind and not a setup-only draft.
    private var keyPicker: some View {
        Menu {
            ForEach(HotkeyBinding.supported) { binding in
                Button(binding.displayName) {
                    rebindForKeyTest(to: binding)
                }
            }
        } label: {
            HStack(spacing: 4) {
                keyCap
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Dictation key")
    }

    private func rebindForKeyTest(to binding: HotkeyBinding) {
        guard coordinator.rebindHotkey(to: binding) else {
            return
        }
        // the new key gets its own six seconds; the picker stays, because
        // taking the offer back the moment it was used would read as a bug.
        keyTest.rearm()
    }

    /// The arrival. Two things the user is about to need and cannot see: which
    /// key, and where the app went — an `LSUIElement` app closing this window
    /// leaves one badge on screen that no string has ever named. Both are
    /// borrowed (the binding settings owns, the badge the menu bar draws), so
    /// nothing here is a second success signal: the lamp's afterglow stays the
    /// only one, and it has no dictation behind it yet.
    ///
    /// Shorter than the checklist it replaces — the window's height is fixed
    /// on purpose, because it used to grow under the pointer.
    private var readyPanel: some View {
        SetupModule {
            VStack(spacing: 14) {
                if onboarding.dictationSelected {
                    HStack(spacing: 7) {
                        Text("Hold")
                        SettingsKeyCap(settings.dictationHotkey.displayName)
                        Text("· talk · let go")
                    }
                    .font(.title3.weight(.medium))
                } else {
                    // meetings-only reaches this card too, and must never be
                    // told to hold a key it has no use for.
                    Text("Pick “Record a Meeting” from that badge.")
                        .font(.title3.weight(.medium))
                }

                HStack(spacing: 8) {
                    // gold stays here: it is the brand's own mark.
                    Image("Badge")
                        .resizable()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text("This badge is Husky, up in your menu bar.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    /// One checklist, filtered by job: nothing here belongs to a job the user
    /// unticked, because a row you cannot need is a row you have to wonder
    /// about.
    private var permissionRows: some View {
        SetupModule {
            permissionRow(
                "Microphone",
                symbol: "mic.fill",
                tint: .orange,
                status: onboarding.microphoneStatus,
                note: "Switch the microphone on for Husky.",
                allow: {
                    permissions.requestMicrophoneAccess {
                        await coordinator.requestMicrophoneAccess()
                    }
                },
                openSettings: permissions.openMicrophoneSettings
            )

            if onboarding.dictationSelected {
                SetupDivider()

                permissionRow(
                    "Accessibility",
                    symbol: "accessibility",
                    tint: .blue,
                    status: onboarding.accessibilityStatus,
                    note: "Find Husky in the list and switch it on.",
                    allow: permissions.requestAccessibilityPrompt,
                    openSettings: permissions.openAccessibilitySettings
                )
            }

            if onboarding.meetingsSelected {
                SetupDivider()
                systemAudioRow
                SetupDivider()
                meetingModelRow

                // nothing new in the happy path: a folder that exists is not
                // news, and only a refusal needs saying.
                if meetingSetup.folderStatus == .actionRequired {
                    SetupDivider()
                    transcriptsFolderRow
                }
            }
        }
    }

    /// Not a question — a demonstration. The app plays its own start sound
    /// into its own tap, which is both the proof and the thing that makes
    /// macOS ask (ADR 0021, ADR 0040). So this row narrates instead of
    /// offering an "allow" button: there is nothing here for you to click
    /// unless it fails.
    @ViewBuilder
    private var systemAudioRow: some View {
        let title = "System audio"
        let symbol = "speaker.wave.2.fill"
        let tint = Color.pink
        switch meetingSetup.systemAudioStatus {
        case .pending:
            SetupRow(symbol: symbol, tint: tint, title: title, detail: "Proved when you click, by playing a sound.") {
                EmptyView()
            }
        case .inProgress:
            SetupRow(symbol: symbol, tint: tint, title: title, detail: "Playing a sound to prove it can hear…") {
                ProgressView().controlSize(.small)
            }
        case .ready:
            SetupRow(symbol: symbol, tint: tint, title: title, detail: nil) {
                StatusDone(text: "Heard it")
            }
        case .actionRequired:
            SetupRow(
                symbol: symbol,
                tint: tint,
                title: title,
                detail: "Couldn't hear. Allow system audio recording in privacy settings.",
                detailIsAlert: true
            ) {
                Button("Open Privacy Settings") {
                    meetingSetup.openSystemAudioSettings()
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    @ViewBuilder
    private var meetingModelRow: some View {
        let title = "Meeting model"
        let symbol = "person.2.fill"
        let tint = Color.orange
        switch meetingSetup.modelStatus {
        case .pending:
            SetupRow(symbol: symbol, tint: tint, title: title, detail: "Downloads when you click.") {
                EmptyView()
            }
        case .inProgress:
            SetupRow(symbol: symbol, tint: tint, title: title, detail: OnboardingJobs.meetingsDownload.onboardingCase) {
                progressBar(meetingSetup.modelProgress)
            }
        case .ready:
            SetupRow(symbol: symbol, tint: tint, title: title, detail: nil) {
                StatusDone(text: "Downloaded")
            }
        case .actionRequired:
            SetupRow(
                symbol: symbol,
                tint: tint,
                title: title,
                detail: "That download didn't finish.",
                detailIsAlert: true
            ) {
                Button("Try Again") { meetingSetup.retryModel() }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var transcriptsFolderRow: some View {
        SetupRow(
            symbol: "folder.fill",
            tint: .cyan,
            title: "Transcripts folder",
            detail: "Couldn't make the meetings folder. Choose another in Settings.",
            detailIsAlert: true
        ) {
            EmptyView()
        }
    }

    /// Says what is true right now, in a word. The previous version showed
    /// three rows reading "pending" before consent had even been given, which
    /// reads as broken rather than waiting.
    /// `note` is the sentence the pane cannot say for us: privacy settings
    /// opens on a list, and which row to touch is the one thing the user is
    /// left guessing. Only shown alongside "open settings" — a granted
    /// permission has nothing to instruct.
    @ViewBuilder
    private func permissionRow(
        _ name: String,
        symbol: String,
        tint: Color,
        status: OnboardingRowStatus,
        note: String? = nil,
        allow: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        switch status {
        case .ready:
            SetupRow(symbol: symbol, tint: tint, title: name, detail: nil) {
                StatusDone(text: "Granted")
            }
        case .actionRequired:
            // default colour: a permission you have not given yet is not a
            // failure, and red is for things that went wrong.
            SetupRow(symbol: symbol, tint: tint, title: name, detail: note) {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.glassProminent)
            }
        case .inProgress:
            SetupRow(symbol: symbol, tint: tint, title: name, detail: "Asking…") {
                ProgressView().controlSize(.small)
            }
        case .pending:
            SetupRow(symbol: symbol, tint: tint, title: name, detail: nil) {
                Button("Allow", action: allow)
                    .buttonStyle(.glassProminent)
            }
        }
    }

    // MARK: - one row, at the bottom, with one way forward

    /// The first version of this screen had a `>` chevron at the top *and* a
    /// "get started" button at the bottom — two controls doing one job, which
    /// is the ambiguity the whole redesign is supposed to be removing. They are
    /// the same control now: the call to action **is** the forward button.
    ///
    /// There is no skip. Someone who launched the app launched it in order to
    /// set it up, and macOS already provides the exit — the window is
    /// `.closable`, and closing it leaves setup to return next launch rather
    /// than silencing it (SPEC §5).
    private var navigation: some View {
        ZStack {
            // Centred independently of the buttons, which are different widths
            // and would otherwise push the dots off-centre.
            if showsPager {
                HStack(spacing: 2) {
                    ForEach(OnboardingStep.allCases) { step in
                        // before the click there is nothing to come back to:
                        // the last screen's "done" works, its two prompts are
                        // live, and no model has been asked for. dimmer, not
                        // gone — a dot that is not yet reads as not yet.
                        let reachable = flow.canJump(
                            to: step,
                            consented: onboarding.consented
                        )
                        let current = step == flow.step

                        Button {
                            move { $0.jump(to: step) }
                        } label: {
                            Capsule()
                                .fill(
                                    current
                                        ? AnyShapeStyle(AppLook.accent)
                                        : AnyShapeStyle(
                                            .primary.opacity(reachable ? 0.25 : 0.1)
                                        )
                                )
                                .frame(width: current ? 18 : 7, height: 7)
                                .padding(5)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!reachable)
                        .accessibilityLabel(
                            step.title(for: onboarding.jobs).onboardingCase
                        )
                        .accessibilityAddTraits(current ? .isSelected : [])
                    }
                }
                .animation(.easeOut(duration: 0.22), value: flow.step)
            }

            HStack {
                Button {
                    move { $0.goBack() }
                } label: {
                    Text("Back")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .opacity(canGoBack ? 1 : 0)
                .disabled(!canGoBack)

                Spacer()

                Button(action: performPrimaryAction) {
                    HStack(spacing: 6) {
                        Text(
                            flow.step.actionTitle(
                                for: onboarding.jobs,
                                verdict: onboarding.verdict
                            )
                            .onboardingCase
                        )
                        Image(systemName: primaryGlyph)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 4)
                }
                // the one prominent control on the surface (ADR 0036);
                // everything else stays quiet.
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                // No job, no setup: there is nothing this click could start.
                .disabled(
                    flow.step == .hello && !onboarding.jobs.anySelected
                )
            }
        }
    }

    /// A reentry about one revoked switch has one screen: dots that walk you
    /// to a welcome card and a `(~3.3 gb)` button are the thing this scope
    /// exists to remove.
    private var showsPager: Bool {
        onboarding.scope != .permissionsOnly
    }

    private var canGoBack: Bool {
        showsPager && flow.canGoBack
    }

    /// The glyph follows the word. A card offering "close" has finished
    /// nothing, so it must not wear a checkmark — SPEC §4's rule, one
    /// screen earlier than it was written for.
    private var primaryGlyph: String {
        guard !flow.canGoForward else {
            return "chevron.right"
        }
        return onboarding.verdict == .incomplete ? "xmark" : "checkmark"
    }

    private func performPrimaryAction() {
        switch flow.step {
        case .hello:
            guard onboarding.jobs.anySelected else {
                return
            }
            onboarding.consentToSetup()
            synchronizePermissions()
            // Kick the downloads off here so they run underneath the rest of
            // setup rather than in front of it. Each job starts its own, and
            // only the ticked ones — "nothing downloads before the click"
            // means nothing you didn't ask for downloads after it either.
            if onboarding.dictationSelected {
                // macOS explains this ask better than any line on this card
                // can, and answering it either way is what registers the app
                // in privacy › accessibility — so "open settings" arrives at
                // a list husky is actually in. Inside the dictation
                // gate: a meetings-only setup is never asked (SPEC §5).
                permissions.requestAccessibilityPrompt()
                coordinator.beginOnboardingEnginePreparation()
            }
            if onboarding.meetingsSelected {
                meetingSetup.begin()
            }
            move { $0.advance() }

        case .model:
            move { $0.advance() }

        case .permissions:
            // the tick lands here and nowhere else. A refusal must not hold
            // the close hostage — the controller keeps the reason and the row
            // prints it the next time this screen is on.
            if loginItem.isAvailable, launchAtLogin != loginItem.isEnabled {
                loginItem.setEnabled(launchAtLogin)
            }
            // "finished" records the press that made it true. Never from an
            // .onChange: it flips `completion`, which the verdict reads, so
            // the ready card would erase itself one frame after arriving.
            onboarding.finishAutomatically()
            coordinator.finishOnboarding(
                dictationWanted: onboarding.scope == .everything
                    ? onboarding.dictationSelected
                    : nil
            )
        }
    }

    // MARK: - keeping the state in step with the system

    private func synchronizeOnboarding() {
        synchronizePermissions()
        synchronizeEngine()
        synchronizeMeetings()
    }

    private func synchronizeMeetings() {
        onboarding.updateSystemAudioStatus(meetingSetup.systemAudioStatus)
        onboarding.updateMeetingModelStatus(meetingSetup.modelStatus)
        // read here too, so the last button reprices the moment the meeting
        // model lands rather than a screen later.
        onboarding.updateMeetingErrand(waiting: coordinator.meetingWaitsOnSetup)
    }

    private func synchronizePermissions() {
        onboarding.updateMicrophoneStatus(
            Self.microphoneRowStatus(for: permissions.microphoneStatus)
        )
        onboarding.updateAccessibility(
            granted: permissions.accessibilityGranted
        )
    }

    private func synchronizeEngine() {
        onboarding.updateModelStatus(
            Self.modelRowStatus(for: coordinator.enginePreparationState)
        )
    }

    private static func microphoneRowStatus(
        for status: AVAuthorizationStatus
    ) -> OnboardingRowStatus {
        switch status {
        case .authorized:
            .ready
        case .denied, .restricted:
            .actionRequired
        case .notDetermined:
            .pending
        @unknown default:
            .pending
        }
    }

    private static func modelRowStatus(
        for state: EnginePreparationState
    ) -> OnboardingRowStatus {
        switch state {
        case .ready:
            .ready
        case .failed:
            .actionRequired
        case .notStarted, .downloading, .warmingUp:
            .pending
        }
    }

    private func bounded(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}

// MARK: - the pieces every screen is made of

/// a group of rows on one glass module, as settings groups them.
private struct SetupModule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .glassModule(cornerRadius: 14)
    }
}

/// a hairline between rows, inset past the icon as System Settings does.
private struct SetupDivider: View {
    var body: some View {
        Divider().padding(.leading, 52)
    }
}

/// one line of setup: an icon, what it is, a line on where it stands, and
/// the one thing to do about it on the right.
private struct SetupRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?
    var detailIsAlert = false
    var detailIsSuccess = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(detailStyle)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .animation(.easeOut(duration: 0.2), value: detail)
    }

    private var detailStyle: AnyShapeStyle {
        if detailIsAlert {
            return AnyShapeStyle(.red)
        }
        if detailIsSuccess {
            return AnyShapeStyle(.green)
        }
        return AnyShapeStyle(.secondary)
    }
}

/// a row's done state: a green tick and one word.
private struct StatusDone: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.green)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private extension String {
    /// the flow's lowercase copy in sentence case, with the app's own name
    /// spelled as macOS would.
    var onboardingCase: String {
        capitalizedFirst.replacingOccurrences(
            of: "husky",
            with: "Husky",
            options: .caseInsensitive
        )
    }
}
