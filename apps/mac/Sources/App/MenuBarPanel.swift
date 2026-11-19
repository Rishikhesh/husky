import AppKit
import SwiftUI
import ThinkingOrbsKit

/// the menu bar icon's panel, in the look every window shares: glass, the
/// Mac's accent and a soft glow at the foot. a header that says whether you
/// can talk, the meeting while one runs (or the record tile), two tiles for
/// what you reach for, today's words, a list of what needs you that is
/// empty when nothing does, and the app's own lines at the foot, read like
/// a menu.
///
/// the rows are the menu's (ADR 0030): nothing here is configuration
/// that belongs in settings. a tile that switches something (the rewrite,
/// the live transcript) leaves the panel up, like control center's; one
/// that goes somewhere closes it.
struct MenuBarPanel: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject var settings: AppSettings
    @ObservedObject var rewrite: RewriteSettings
    @ObservedObject var updates: DailyUpdateCheck
    @ObservedObject var updateHandOff: UpdateHandOff

    @Environment(\.openSettings) private var openSettings
    @State private var window: NSWindow?
    /// the last seven days' words from the archive, oldest first; nil until
    /// read, or when nothing is kept to count.
    @State private var week: [DashboardStats.DayWords]?

    static let width: CGFloat = 320

    private struct WeekKey: Equatable {
        let lastHeard: String?
        let keeps: Bool
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if showsMeetingModule {
                meetingModule
            } else {
                recordTile
            }
            HStack(spacing: 10) {
                rewriteTile
                fixAWordTile
            }
            if settings.keepDictations, let week {
                todayStrip(week)
            }
            if !notices.isEmpty {
                noticesModule
            }
            footer
        }
        .padding(12)
        .frame(width: Self.width)
        // the window is sized from the content, and without this the
        // stack is squeezed to fit a guess: tiles shrink under their own
        // glyphs and the second lines fall out of their modules.
        .fixedSize(horizontal: false, vertical: true)
        .background { BottomGlow(size: 260) }
        .tint(AppLook.accent)
        .background(PanelWindowReader { window = $0 })
        // read again after every take, so today's count is today's, and
        // when keeping is switched.
        .task(id: WeekKey(lastHeard: coordinator.lastHeard, keeps: settings.keepDictations)) {
            await readWeek()
        }
    }

    /// the panel goes the way a menu goes once something is chosen.
    private func close() {
        window?.close()
    }

    private func showSettings() {
        close()
        NSApp.activate()
        openSettings()
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 10) {
            ThinkingOrb(
                state: OrbState(rawValue: settings.listeningOrb.rawValue) ?? .composing,
                theme: .auto,
                displaySize: 38
            )
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Husky")
                        .font(.system(size: 13.5, weight: .semibold))
                    // two icons that look the same is a bad time, so the
                    // dev build says so here.
                    if Capabilities.current.announcesItself {
                        Text("Dev")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                            .help("Dev build — \(AppIdentity.bundleID)")
                    }
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                    Text(status.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 8)
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    /// whether you can talk. "ready" alone is furniture, so it says how.
    private var status: (text: String, color: Color) {
        if coordinator.needsAttention {
            return ("Setup isn't finished", .red)
        }
        if coordinator.meetings.isRecording {
            return ("Recording a meeting", .red)
        }
        if coordinator.state != .idle {
            return (coordinator.state.displayName.capitalizedFirst, AppLook.accent)
        }
        // a model switch runs on its own: say so wherever you look.
        let target = settings.dictationModel
        if target != coordinator.activeDictationModel {
            switch coordinator.enginePreparationState {
            case let .downloading(progress):
                return ("Downloading \(target.shortName) · \(Int((progress * 100).rounded()))%", AppLook.accent)
            case .warmingUp:
                return ("Loading \(target.shortName) · about a minute", AppLook.accent)
            case .notStarted, .ready, .failed:
                break
            }
        }
        return ("Ready · hold \(settings.dictationHotkey.displayName) to talk", .green)
    }

    // MARK: - meetings

    /// a meeting owns the panel's first module while it runs (ADR 0023),
    /// getting ready and writing out included.
    private var showsMeetingModule: Bool {
        coordinator.meetings.isRecording
            || coordinator.meetings.phase.menuLine(elapsed: .zero) != nil
    }

    private var meetingModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RecordingDot(isLive: coordinator.meetings.isRecording)
                // the clock reads the coordinator each second; the panel
                // stays up and must tick.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(
                        (coordinator.meetings.phase.menuLine(
                            elapsed: coordinator.meetings.elapsed
                        ) ?? "recording").capitalizedFirst
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(2)
                }
                Spacer(minLength: 0)
                // on the clock's line, not beside stop: with "hide live
                // transcript" the second line has no width to spare. it is
                // here while the meeting is written out too, because that
                // is when the notes arrive.
                Button("Open") {
                    close()
                    coordinator.openMeetings()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel("Open the meetings window")
            }
            if coordinator.meetings.isRecording {
                HStack(spacing: 8) {
                    Button(
                        coordinator.isLiveTranscriptShown
                            ? "Hide Live Transcript"
                            : "Live Transcript"
                    ) {
                        coordinator.toggleLiveTranscript()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    Spacer(minLength: 0)
                    Button {
                        close()
                        coordinator.stopMeeting()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Stop")
                            KeyCaps(["⌘", "⇧", "."], onTint: true)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassModule()
    }

    /// nothing starts a recording but you (ADR 0023, 0047). a call nobody
    /// records leads the tile's second line for as long as it lasts; the
    /// other meeting models on this mac are behind its chevron.
    private var recordTile: some View {
        HStack(spacing: 0) {
            Button {
                close()
                coordinator.startMeeting()
            } label: {
                TileLabel(hovers: true) {
                    HStack(spacing: 11) {
                        TileGlyph(symbol: "record.circle", isOn: false, tint: .red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Record a Meeting")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(
                                coordinator.unrecordedCall.map {
                                    "Call in \($0) · not recording"
                                } ?? "Hears the whole Mac"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(coordinator.unrecordedCall != nil ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if let shortcut = settings.meetingShortcut {
                            KeyCaps(shortcut.keyCaps)
                        }
                    }
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Record a meeting")

            let others = coordinator.recordWithChoices
            if !others.isEmpty {
                Menu {
                    Section("Record with") {
                        ForEach(others, id: \.model) { choice in
                            Button(choice.title) {
                                close()
                                coordinator.startMeeting(model: choice.model)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 52)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Record with another model")
            }
        }
        .glassModule()
    }

    // MARK: - tiles

    /// a switch, like control center's: the panel stays up.
    private var rewriteTile: some View {
        let modifier = settings.dictationHotkey.rewriteModifier(
            preferring: rewrite.modifier
        )
        return Button {
            rewrite.isEnabled.toggle()
        } label: {
            TileLabel(hovers: true) {
                VStack(alignment: .leading, spacing: 9) {
                    TileGlyph(symbol: "wand.and.sparkles", isOn: rewrite.isEnabled, tint: AppLook.accent)
                    TileWords(
                        title: "Rewrite",
                        subtitle: rewrite.isEnabled
                            ? "On · \(settings.dictationHotkey.displayName) + \(modifier.symbol)"
                            : "Off"
                    )
                }
            }
        }
        .buttonStyle(PressStyle())
        .glassModule()
        .accessibilityLabel("Rewrite")
        .accessibilityValue(rewrite.isEnabled ? "On" : "Off")
        .accessibilityAddTraits(rewrite.isEnabled ? .isSelected : [])
    }

    /// the one time-sensitive action (ADR 0030): you just watched it
    /// mishear a name.
    private var fixAWordTile: some View {
        Button {
            close()
            coordinator.openWordFixer()
        } label: {
            TileLabel(hovers: coordinator.lastHeard != nil) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        TileGlyph(symbol: "character.cursor.ibeam", isOn: false, tint: AppLook.accent)
                        Spacer(minLength: 4)
                        if let shortcut = settings.fixAWordShortcut {
                            KeyCaps(shortcut.keyCaps)
                        }
                    }
                    TileWords(
                        title: "Fix a Word",
                        subtitle: coordinator.lastHeard == nil
                            ? "After your first dictation"
                            : "Teach it a word"
                    )
                }
            }
        }
        .buttonStyle(PressStyle())
        .disabled(coordinator.lastHeard == nil)
        .opacity(coordinator.lastHeard == nil ? 0.55 : 1)
        .glassModule()
        .accessibilityLabel("Fix a word")
    }

    // MARK: - today

    private func todayStrip(_ week: [DashboardStats.DayWords]) -> some View {
        let today = week.last?.words ?? 0
        let most = max(week.map(\.words).max() ?? 0, 1)
        return HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(today.formatted())
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(today == 1 ? "word today" : "words today")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(week, id: \.day) { day in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(day.isToday ? AnyShapeStyle(AppLook.accent) : AnyShapeStyle(.primary.opacity(0.12)))
                        .frame(width: 6, height: max(2, 24 * CGFloat(day.words) / CGFloat(most)))
                }
            }
            .frame(height: 24, alignment: .bottom)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassModule()
        .accessibilityElement(children: .combine)
    }

    /// off the main thread: the archive is a file that grows for years.
    // ponytail: reads the whole archive per take, as Home does; an index
    // by day if it ever shows.
    private func readWeek() async {
        guard settings.keepDictations else {
            week = nil
            return
        }
        let dictations = await Task.detached(priority: .utility) {
            (try? DictationArchive().all()) ?? []
        }.value
        week = DashboardStats.make(
            dictations: dictations,
            totalWords: 0,
            typicalPaste: nil,
            slowestPaste: nil,
            pasteSample: 0,
            keepsDictations: true,
            now: .now,
            calendar: .current
        ).lastSevenDays
    }

    // MARK: - what needs you

    private struct Notice: Identifiable {
        let id: String
        let symbol: String
        let text: String
        let action: String
        var isAttention = false
        var isEnabled = true
        let perform: () -> Void
    }

    /// zero rows when everything works. each one goes on its own when it
    /// is no longer true, as the menu's rows did.
    private var notices: [Notice] {
        var notices: [Notice] = []
        if coordinator.needsAttention {
            notices.append(Notice(
                id: "setup", symbol: "exclamationmark.triangle.fill",
                text: "Setup isn't finished", action: "Finish setup…",
                isAttention: true
            ) { [coordinator] in
                coordinator.runOnboardingAgain()
            })
        }
        if !coordinator.meetings.isRecording, coordinator.meetingsNeedAttention {
            notices.append(Notice(
                id: "systemAudio", symbol: "speaker.slash.fill",
                text: "Meetings can't hear the Mac", action: "Fix…",
                isAttention: true
            ) { [coordinator] in
                coordinator.runOnboardingAgain(
                    scope: .meetingsOnly, openAt: .permissions)
            })
        }
        if !coordinator.meetings.isRecording, coordinator.canRetryLastFailure {
            notices.append(Notice(
                id: "retry", symbol: "arrow.clockwise",
                text: "The last take didn't land", action: "Try again"
            ) { [coordinator] in
                coordinator.retryLastFailure()
            })
        }
        if !coordinator.meetings.isRecording,
           let learned = coordinator.undoableLearning {
            notices.append(Notice(
                id: "learned", symbol: "book.closed",
                text: "Learned “\(learned.right)”", action: "Undo"
            ) { [coordinator] in
                coordinator.undoLearning()
            })
        }
        if !coordinator.meetings.isRecording, coordinator.showsLastMeetingRow {
            notices.append(Notice(
                id: "lastMeeting", symbol: "doc.text",
                text: "The meeting is saved", action: "Show in Finder"
            ) { [coordinator] in
                coordinator.revealLastMeeting()
            })
        }
        // a newer version is a line and nothing else (ADR 0043), and waits
        // for a meeting to end.
        if !coordinator.meetings.isRecording,
           let line = updateHandOff.state(offering: updates.line) {
            notices.append(Notice(
                id: "update", symbol: "arrow.down.circle",
                text: line.title.capitalizedFirst, action: Self.updateAction(line),
                isEnabled: line.isEnabled
            ) { [updateHandOff, updates] in
                updateHandOff.click(offering: updates.line)
            })
        }
        return notices
    }

    private static func updateAction(_ line: UpdateOffer.LineState) -> String {
        switch line {
        case .available: "Update"
        case .updating: "Updating…"
        case .restartToFinish: "Restart"
        case .failedCopied: "Try again"
        }
    }

    private var noticesModule: some View {
        VStack(spacing: 0) {
            ForEach(Array(notices.enumerated()), id: \.element.id) { index, notice in
                if index > 0 {
                    Divider().padding(.leading, 40)
                }
                HStack(spacing: 10) {
                    Image(systemName: notice.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(notice.isAttention ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(notice.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    noticeButton(notice)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 2)
        .glassModule()
    }

    /// setup's is the one that leads, in the accent.
    @ViewBuilder
    private func noticeButton(_ notice: Notice) -> some View {
        let button = Button(notice.action) {
            close()
            notice.perform()
        }
        .controlSize(.small)
        .disabled(!notice.isEnabled)
        if notice.isAttention {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    // MARK: - foot

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuRow("Meetings") {
                close()
                coordinator.openMeetings()
            }
            MenuRow("Settings…", keys: ["⌘", ","], action: showSettings)
                .keyboardShortcut(",")
            MenuSeparator()
            MenuRow("About Husky") {
                close()
                coordinator.openAbout()
            }
            // what a friend sends instead of a story: the last fifty
            // presses and how each ended, never a word of what was said.
            MenuRow("Copy Diagnostics") {
                close()
                coordinator.copyDiagnostics()
            }
            if hasDevRow {
                MenuSeparator()
                if Capabilities.current.canResetInPlace {
                    MenuRow("Reset & Relaunch") {
                        close()
                        coordinator.resetInPlaceForDevelopment()
                    }
                }
                #if DEBUG
                if Capabilities.current.hasLampLab {
                    MenuRow("Lamp Lab") {
                        close()
                        coordinator.openLampLab()
                    }
                    MenuRow("Rehearse the Lamp") {
                        close()
                        coordinator.rehearseHUDForDevelopment()
                    }
                }
                #endif
            }
            MenuSeparator()
            MenuRow("Quit", keys: ["⌘", "Q"]) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.top, 2)
    }

    private var hasDevRow: Bool {
        #if DEBUG
        Capabilities.current.canResetInPlace || Capabilities.current.hasLampLab
        #else
        Capabilities.current.canResetInPlace
        #endif
    }
}

// MARK: - the pieces

/// a press you can feel: a little smaller while held, back on release.
/// held still with Reduce Motion.
private struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// a tile's face: its content, padded, lit faintly on hover.
private struct TileLabel<Content: View>: View {
    var hovers: Bool
    @ViewBuilder let content: Content

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(shape.fill(.primary.opacity(isHovered && hovers ? 0.05 : 0)))
            .contentShape(shape)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// control center's round glyph: lit in the tint when on.
private struct TileGlyph: View {
    let symbol: String
    let isOn: Bool
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(tint == .red ? .red : .primary))
            .frame(width: 32, height: 32)
            .background(Circle().fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.primary.opacity(0.09))))
            .animation(.easeOut(duration: 0.2), value: isOn)
            .accessibilityHidden(true)
    }
}

private struct TileWords: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// a shortcut as small key caps, one per key, the way the mock and a
/// menu write it.
struct KeyCaps: View {
    let keys: [String]
    /// on a coloured button: white caps on a lighter wash.
    var onTint = false

    init(_ keys: [String], onTint: Bool = false) {
        self.keys = keys
        self.onTint = onTint
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(minWidth: 17)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(onTint ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.primary.opacity(0.09)))
                    )
            }
        }
        .foregroundStyle(onTint ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        .accessibilityElement()
        .accessibilityLabel(keys.joined())
    }
}

/// a line at the foot that reads like a menu item: lit in the accent on
/// hover, its shortcut at the end.
private struct MenuRow: View {
    let title: String
    var keys: [String] = []
    let action: () -> Void

    init(_ title: String, keys: [String] = [], action: @escaping () -> Void) {
        self.title = title
        self.keys = keys
        self.action = action
    }

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                if !keys.isEmpty {
                    Text(keys.joined())
                        .font(.system(size: 12))
                        .foregroundStyle(isHovered ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                }
            }
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(AppLook.accent) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

/// a meeting's red dot, breathing while it records; still with Reduce
/// Motion.
private struct RecordingDot: View {
    let isLive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(isLive ? Color.red : Color.secondary)
            .frame(width: 10, height: 10)
            .opacity(dim ? 0.35 : 1)
            .animation(
                isLive && !reduceMotion
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: dim
            )
            .onAppear { dim = isLive && !reduceMotion }
            .onChange(of: isLive) { dim = isLive && !reduceMotion }
            .accessibilityHidden(true)
    }
}

/// the window the panel is drawn in, for closing it the way a menu
/// closes: `MenuBarExtra` has no dismiss of its own.
private struct PanelWindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            found(view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Task { @MainActor in
            found(view.window)
        }
    }
}
