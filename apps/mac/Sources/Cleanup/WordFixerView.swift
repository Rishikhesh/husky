import AppKit
import SwiftUI

/// fix a word: what the engine heard, laid out as words you point at. the
/// one you point at is picked in the accent; one you saved turns green.
struct WordFixerView: View {
    @ObservedObject var viewModel: WordFixerViewModel
    /// fix a word's global shortcut, for the footnote; nil when cleared.
    let shortcut: MeetingShortcut?
    let close: () -> Void

    @State private var lineCopied = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What it heard")
                .font(.system(size: 15, weight: .semibold))
            Text("Click a word that came out wrong. Click the one next to it to take both.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, 12)

            // only the words scroll. a 200-word dictation used to lay the
            // picker row and the footer out past the bottom edge, so you
            // could see the word you wanted to fix and not reach the field
            // that fixes it.
            ScrollView {
                WordFlow(spacing: 4) {
                    ForEach(viewModel.correction.spans) { span in
                        WordChip(
                            text: viewModel.saved[span.id] ?? span.text,
                            isSaved: viewModel.saved[span.id] != nil,
                            isSelected: isSelected(span.id)
                        ) {
                            viewModel.tap(span.id)
                            fieldFocused = true
                        }
                    }
                }
                // a concrete width proposal, or the flow falls back to its
                // hardcoded 480 and stops tracking a resized window.
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassModule(cornerRadius: 12)

            fixRow
                .frame(minHeight: 30)
                .padding(.top, 14)

            if let failure = viewModel.failure {
                Text(failure.capitalizedFirst)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }

            footnote
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // esc closes, as it closes any small window that asks one thing.
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .glassWindow()
    }

    /// heard → what you meant, and save. before a pick, what to do; after
    /// a save, what it means.
    @ViewBuilder
    private var fixRow: some View {
        if let phrase = viewModel.selectedPhrase {
            HStack(spacing: 8) {
                Text("“\(phrase)” →")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TextField("What you meant", text: $viewModel.replacement)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.primary.opacity(0.08)))
                    .overlay(
                        Capsule().strokeBorder(
                            AppLook.accent.opacity(fieldFocused ? 0.6 : 0), lineWidth: 2)
                    )
                    .animation(.easeOut(duration: 0.15), value: fieldFocused)
                    .focused($fieldFocused)
                    .onSubmit { viewModel.save() }
                Button("Save") { viewModel.save() }
                    .buttonStyle(.glassProminent)
                    .disabled(!viewModel.canSave)
            }
        } else if !viewModel.saved.isEmpty {
            Text("Saved. Husky will write it that way from now on, everywhere.")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        } else {
            Text("Pick a word above.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private var footnote: some View {
        HStack(spacing: 6) {
            if let shortcut {
                KeyCaps(shortcut.keyCaps)
                Text("opens this from anywhere, on your last dictation. Esc closes it.")
            } else {
                Text("Esc closes it.")
            }
            Spacer(minLength: 8)
            // "from now on" left out the one dictation you came here
            // about. no pill and no auto-paste: focus is long gone, so the
            // button's own label is the whole receipt.
            if !viewModel.saved.isEmpty {
                Button(lineCopied ? "Copied" : "Copy the fixed line", action: copyFixedLine)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.tertiary)
    }

    /// the same shape and the same 1.2 s as the about window's copy button,
    /// so the app's two transient copy buttons behave identically.
    private func copyFixedLine() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.fixedLine, forType: .string)
        lineCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            lineCopied = false
        }
    }

    private func isSelected(_ index: Int) -> Bool {
        guard let first = viewModel.first, let last = viewModel.last else {
            return false
        }
        return (first...last).contains(index)
    }
}

private struct WordChip: View {
    let text: String
    let isSaved: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button(action: action) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(isSaved ? AnyShapeStyle(.green) : AnyShapeStyle(.primary))
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(AppLook.accent.opacity(isSelected ? 1 : 0), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isSaved)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(AppLook.accent.opacity(0.22))
        }
        return AnyShapeStyle(.primary.opacity(isHovered && !isSaved ? 0.09 : 0))
    }
}

/// Words wrap like words. `HStack` would push a long transcript off the window.
private struct WordFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 480
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

@MainActor
final class WordFixerWindowController: NSWindowController {
    init(
        transcript: String,
        store: DictionaryStore,
        cleanupOptions: CleanupOptions = CleanupOptions(),
        shortcut: MeetingShortcut? = nil
    ) {
        let viewModel = WordFixerViewModel(
            transcript: transcript,
            store: store,
            options: cleanupOptions
        )
        // the view closes its window on esc; the window is made after it.
        weak var closing: NSWindow?
        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: WordFixerView(
                    viewModel: viewModel,
                    shortcut: shortcut,
                    close: { closing?.performClose(nil) }
                )
            )
        )
        closing = window
        window.title = "Fix a Word"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 500, height: 400))
        window.minSize = NSSize(width: 420, height: 280)
        window.isReleasedWhenClosed = false
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
