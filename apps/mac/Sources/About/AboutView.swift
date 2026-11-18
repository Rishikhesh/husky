import AppKit
import Combine
import SwiftUI

/// the about window is a stamp, not a page: apple's own panel is 284×159
/// with the content sitting directly on the window — no visible title bar.
/// same recipe here, on the shared glass in the Mac's Light or Dark.
/// (docs/research/about-windows.md)
@MainActor
final class AboutWindowController: NSWindowController {
    init(
        bundle: Bundle = .main,
        settings: AppSettings = .shared
    ) {
        let rootView = AboutView(bundle: bundle, settings: settings)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Husky"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let size = NSSize(width: 300, height: AboutView.height)
        window.setContentSize(size)
        window.minSize = size
        window.maxSize = size
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.center()

        super.init(window: window)
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
}

struct AboutView: View {
    static let height: CGFloat = 412

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case newer(String, URL)
        /// the bundle in /Applications is already the new one — brew swapped
        /// it, and this process is the copy that was running at the time.
        case alreadyInstalled(String)
        case unreachable
    }

    @ObservedObject private var settings: AppSettings
    @State private var showsRecord = false
    @State private var versionCopied = false
    @State private var upgradeCopied = false
    @State private var updateStatus: UpdateStatus = .idle
    @State private var showsLicences = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let version: String
    private let build: String
    /// brew put it there, brew replaces it. a dmg user handed a `brew upgrade`
    /// line would paste an error into their terminal, so they get sent to the
    /// page the dmg is on instead.
    private let installedByHomebrew: Bool

    init(
        bundle: Bundle = .main,
        settings: AppSettings = .shared
    ) {
        _settings = ObservedObject(wrappedValue: settings)

        let shortVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = bundle.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        version = shortVersion ?? "development"
        self.build = build ?? "development"
        installedByHomebrew = UpdateOffer.Install.detect() == .homebrew
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showsRecord.toggle()
                }
            } label: {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 104, height: 104)
            }
            .buttonStyle(PressScale(reduceMotion: reduceMotion))
            .accessibilityLabel("Husky")
            .accessibilityHint("Shows how many words Husky has typed")

            Text("Husky")
                .font(.title2.weight(.semibold))
                .padding(.top, 8)

            taglineOrRecord
                .padding(.top, 3)

            Button {
                copyVersion()
            } label: {
                Text(versionCopied ? "Copied" : "Version \(version) (\(build))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: versionCopied)
            }
            .buttonStyle(.plain)
            .help("Click to copy")
            .padding(.top, 6)

            updatesArea
                .padding(.top, 14)
                .animation(.easeOut(duration: 0.2), value: updateStatus)
                .animation(.easeOut(duration: 0.15), value: upgradeCopied)

            Spacer(minLength: 14)

            // six names no longer fit one line, so it wraps, and wrapped
            // text leans left unless told otherwise.
            Text(creditsMarkdown)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            signatureLine
                .padding(.top, 8)
        }
        .padding(.top, 30)
        .padding(.bottom, 18)
        .padding(.horizontal, 18)
        .frame(width: 300, height: Self.height)
        .glassWindow()
        // brew can swap the bundle while this window sits open, so the line
        // rechecks the disk when the window appears and whenever the app is
        // brought forward. no network in either path.
        .task {
            noteAnyUpgradeOnDisk()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            noteAnyUpgradeOnDisk()
        }
    }

    /// one slot, two lines. the tagline is the screen; the lifetime word
    /// count is the reward for poking husky.
    @ViewBuilder
    private var taglineOrRecord: some View {
        ZStack {
            if showsRecord {
                Text(lifetimeWordsText)
                    .foregroundStyle(AppLook.accent)
                    .transition(.opacity)
            } else {
                Text("Escape the keyboard.")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var lifetimeWordsText: String {
        let count = settings.totalWordsDictated.formatted(
            .number.grouping(.automatic)
        )
        return "Husky has typed \(count) words. Undefeated."
    }

    /// what each part is licensed under, shown from the signature line.
    private static let licences: [(String, String)] = [
        ("FluidAudio", "Apache-2.0"),
        ("Parakeet weights", "CC-BY-4.0"),
        ("WhisperKit", "MIT"),
        ("Whisper weights", "MIT"),
        ("Needle engine and Whistle weights", "Apache-2.0"),
        ("Silero VAD", "MIT"),
        ("This app", "MIT"),
    ]

    // single literals, not `+` chains: a chain of eight string literals
    // sent the release compiler into "unable to type-check in reasonable
    // time" and failed a tag build.
    private static let creditsSource = """
        Built on [FluidAudio](https://github.com/FluidInference/FluidAudio), \
        [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2), \
        [WhisperKit](https://github.com/argmaxinc/WhisperKit), \
        [Whisper](https://github.com/openai/whisper), \
        [Whistle](https://huggingface.co/Cactus-Compute/whistle) \
        and [Silero](https://github.com/snakers4/silero-vad).
        """

    private var creditsMarkdown: AttributedString {
        (try? AttributedString(markdown: Self.creditsSource))
            ?? AttributedString(
                "Built on FluidAudio, Parakeet, WhisperKit, Whisper, Whistle and Silero."
            )
    }

    private static let signatureSource = """
        [Made by Rishikhesh](https://github.com/Rishikhesh/husky) · \
        based on [Andrew Dictate by jass](https://github.com/jassuwu/andrew-dictate) \
        and [Suriya's fork](https://github.com/suriyavasan/andrew-dictate)
        """

    /// who made it, whose build this is, the source, and the licences.
    private var signatureLine: some View {
        VStack(spacing: 4) {
            Text(
                (try? AttributedString(markdown: Self.signatureSource))
                    ?? AttributedString("Made by Rishikhesh · based on Andrew Dictate by jass and Suriya's fork")
            )
            .multilineTextAlignment(.center)

            Button("Licences") { showsLicences.toggle() }
                .buttonStyle(.link)
                .popover(isPresented: $showsLicences, arrowEdge: .bottom) {
                    licencesList
                }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var licencesList: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(Self.licences, id: \.0) { part, licence in
                GridRow {
                    Text(part)
                    Text(licence)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .padding(14)
    }

    /// asks github only when clicked, and a tag that doesn't parse never
    /// says "upgrade" — the quiet failure is "couldn't check", not a lie.
    @ViewBuilder
    private var updatesArea: some View {
        Group {
            switch updateStatus {
            case .idle:
                Button("Check for Updates") { checkForUpdates() }
                    .buttonStyle(.glass)
                    .controlSize(.small)

            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking…")
                }
                .foregroundStyle(.secondary)

            case .upToDate:
                Label("You’re on the latest version.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)

            case let .newer(version, page):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Version \(version) is out")
                            .fontWeight(.medium)
                        Spacer(minLength: 0)
                        Link("What’s New", destination: page)
                    }
                    upgradeInstruction
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassModule(cornerRadius: 12)

            case let .alreadyInstalled(version):
                HStack(spacing: 8) {
                    Text("Version \(version) is installed.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Restart Husky") { AppRelaunch.now() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                        .help("Quits Husky and opens it again")
                }
                .padding(10)
                .glassModule(cornerRadius: 12)

            case .unreachable:
                Text("Couldn’t check. Try again later.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .transition(.opacity)
    }

    /// the command, not a tab: every copy was installed with one brew line,
    /// so the update is one brew line — and it is the whole instruction,
    /// because brew carries the gatekeeper approval and the permission grants
    /// across. a github page would teach a dmg drag nobody here did.
    @ViewBuilder
    private var upgradeInstruction: some View {
        if installedByHomebrew {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    copyUpgradeCommand()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(
                            upgradeCopied
                                ? "Copied. Paste it in Terminal."
                                : UpdateCheck.upgradeCommand
                        )
                        .font(
                            upgradeCopied
                                ? .caption
                                : .system(size: 10, design: .monospaced)
                        )
                        .multilineTextAlignment(.leading)
                        // two lines are reserved either way, so the flash
                        // cannot shuffle everything under it.
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: upgradeCopied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        .primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to copy")

                Text("No xattr step — your permissions stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("The new DMG is on the release page.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// the upgrade may have already landed: brew replaces the bundle under a
    /// running app, so ask the disk before asking github. costs one plist
    /// read and no network.
    private func noteAnyUpgradeOnDisk() {
        guard let installed = UpdateCheck.installedVersion(
            atBundle: Bundle.main.bundleURL
        ),
            UpdateCheck.isNewer(tag: installed, than: version)
        else {
            return
        }
        updateStatus = .alreadyInstalled(installed)
    }

    private func checkForUpdates() {
        noteAnyUpgradeOnDisk()
        if case .alreadyInstalled = updateStatus {
            return
        }

        updateStatus = .checking
        Task {
            do {
                let latest = try await UpdateCheck.fetchLatest()
                updateStatus = UpdateCheck.isNewer(
                    tag: latest.version,
                    than: version
                )
                    ? .newer(
                        UpdateCheck.numbers(in: latest.version)
                            .map(String.init)
                            .joined(separator: "."),
                        latest.page
                    )
                    : .upToDate
            } catch {
                updateStatus = .unreachable
            }
        }
    }

    private func copyVersion() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "\(version) · build \(build)",
            forType: .string
        )
        versionCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            versionCopied = false
        }
    }

    private func copyUpgradeCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(UpdateCheck.upgradeCommand, forType: .string)
        upgradeCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            upgradeCopied = false
        }
    }
}

/// a pressed icon gives a little, the way a Dock icon does. still with
/// Reduce Motion.
private struct PressScale: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
