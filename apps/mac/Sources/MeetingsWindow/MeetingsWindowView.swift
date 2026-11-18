import SwiftUI

/// the meetings window: the list on the left, one meeting on the right, and
/// the recording bar along the bottom of that, over whatever is open.
struct MeetingsWindowView: View {
    @ObservedObject var state: MeetingsWindowState
    @ObservedObject var library: MeetingsLibraryModel
    @ObservedObject var summaries: MeetingSummaries

    @State private var columns = NavigationSplitViewVisibility.all

    init(state: MeetingsWindowState) {
        self.state = state
        library = state.library
        summaries = state.summaries
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            MeetingsSidebar(state: state, library: library, summaries: summaries)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MeetingRecordBar(state: state, library: library, summaries: summaries)
                }
        }
        .navigationSplitViewStyle(.balanced)
        // the Mac's own Light or Dark and its accent, with a green glow at
        // the foot: green is meetings' colour, as red is a recording's.
        .glassWindow(glow: .green)
        .frame(minWidth: 920, minHeight: 560)
        .alert(deleteTitle, isPresented: isDeleting) {
            Button("Delete", role: .destructive) { state.confirmDelete() }
            Button("Cancel", role: .cancel) { state.pendingDelete = nil }
        } message: {
            Text("The transcript goes to the Trash, with its audio.")
        }
        .alert(
            (library.failure ?? "").capitalizedFirst,
            isPresented: Binding(
                get: { library.failure != nil },
                set: { if !$0 { library.dismissFailure() } })
        ) {
            Button("OK", role: .cancel) {}
        }
        .background {
            // ⌘W closes it, as any window.
            Button("") { (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    // MARK: the detail column

    @ViewBuilder
    private var detail: some View {
        switch library.selection {
        case .recording?:
            RecordingDetailView(state: state)
        case let .meeting(url)?:
            if let entry = library.entry(for: url), let document = library.document(for: url) {
                MeetingDetailView(
                    state: state, library: library, summaries: summaries,
                    entry: entry, document: document)
                    .id(url)
            } else {
                // just saved, and the list has not read it yet; or gone.
                Color.clear
            }
        case nil:
            if library.hasLoaded, library.entries.isEmpty {
                emptyState
            } else {
                Color.clear
            }
        }
    }

    /// System Settings' empty pane: the icon, one sentence, the one thing
    /// to do.
    private var emptyState: some View {
        VStack(spacing: MW.s16) {
            IconTile(symbol: "waveform.badge.mic", tint: .green, size: 60)
            Text("Record a call and Husky writes it up, with a summary and a transcript.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button {
                state.recordNew()
            } label: {
                Label("Record a Meeting", systemImage: "record.circle")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.top, MW.s8)
            .disabled(state.isBusy)
        }
        .padding(MW.s24)
    }

    // MARK: deleting

    private var isDeleting: Binding<Bool> {
        Binding(
            get: { state.pendingDelete != nil },
            set: { if !$0 { state.pendingDelete = nil } })
    }

    private var deleteTitle: String {
        guard let url = state.pendingDelete, let entry = library.entry(for: url) else {
            return "Delete this meeting?"
        }
        return "Delete “\(entry.title)”?"
    }
}
