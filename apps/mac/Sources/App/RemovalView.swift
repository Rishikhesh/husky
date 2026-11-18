import AppKit
import SwiftUI

/// Leaving, made as easy as arriving.
struct RemovalView: View {
    // owned here, not passed in: as sheet content this view gets rebuilt on
    // every settings re-render, and an inline-constructed model was reborn
    // blank each time — wiping the failure message mid-read (ADR 0035).
    @StateObject private var viewModel = RemovalViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: "trash", tint: .red, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove what’s on this Mac")
                        .font(.title3.weight(.semibold))
                    Text(
                        viewModel.hasAnythingToRemove
                            ? "Everything is ticked. Untick anything you want to keep."
                            : "There’s nothing left to remove."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().padding(.leading, 26)
                    }
                    RemovalRow(
                        entry: entry,
                        sizeText: viewModel.sizeText(for: entry),
                        isOn: viewModel.selection.contains(entry.item),
                        toggle: { viewModel.toggle(entry.item) }
                    )
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .glassModule(cornerRadius: 12)

            Toggle(
                "Also move Husky to the Trash",
                isOn: $viewModel.alsoTrashTheApp
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassModule(cornerRadius: 12)

            // The one thing the app genuinely cannot do for you. Saying so
            // beats letting someone believe "no traces" covered it.
            VStack(alignment: .leading, spacing: 2) {
                Text("macOS keeps the microphone and Accessibility permissions.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security…") {
                    NSWorkspace.shared.open(
                        URL(
                            string: "x-apple.systempreferences:"
                                + "com.apple.preference.security?Privacy_Accessibility"
                        )!
                    )
                }
                .buttonStyle(.link)
            }
            .font(.caption)

            if let outcome = viewModel.outcome {
                Text(outcome.capitalizedFirst)
                    .font(.body)
                    .foregroundStyle(
                        outcome.hasPrefix("couldn")
                            ? AnyShapeStyle(.red)
                            : AnyShapeStyle(.secondary)
                    )
            }

            if let detail = viewModel.failureDetail {
                // six reasons with long paths would push the sheet past the
                // bottom of the screen, which is the clipping again from the
                // other side. the reasons scroll; the way out does not move.
                ScrollView {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            Spacer(minLength: 0)

            HStack {
                Text(
                    viewModel.selectedBytes > 0
                        ? "Frees \(viewModel.selectedSizeText)"
                        : " "
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)

                Button("Remove", role: .destructive) { remove() }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .disabled(viewModel.selection.isEmpty || isWorking)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tint(AppLook.accent)
        .onAppear { viewModel.reload() }
    }

    private func remove() {
        isWorking = true
        let failed = viewModel.removeSelected()
        let trash = viewModel.alsoTrashTheApp

        guard failed.isEmpty else {
            // Something is still on disk. Stay open and say which — quitting
            // here would look exactly like success.
            isWorking = false
            return
        }

        Task { @MainActor in
            // Long enough to read "removed. quitting."
            try? await Task.sleep(for: .milliseconds(900))
            if trash {
                _ = try? await NSWorkspace.shared.recycle(
                    [Bundle.main.bundleURL]
                )
            }
            dismiss()
            NSApp.terminate(nil)
            // terminate can be politely refused while a sheet is still
            // coming down — and then nothing here was interactive anymore.
            // the data is already off the disk; the user asked for gone.
            try? await Task.sleep(for: .milliseconds(700))
            exit(0)
        }
    }
}

private struct RemovalRow: View {
    let entry: RemovalPlan.Entry
    let sizeText: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle(
                "",
                isOn: Binding(get: { isOn }, set: { _ in toggle() })
            )
            .labelsHidden()
            .disabled(!entry.exists)
            .accessibilityLabel(entry.item.title)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.title.capitalizedFirst)
                    .font(.body)
                    .foregroundStyle(
                        entry.exists
                            ? AnyShapeStyle(.primary)
                            : AnyShapeStyle(.secondary)
                    )
                if entry.exists, let caveat = entry.item.caveat {
                    Text(caveat.capitalizedFirst)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(sizeText.capitalizedFirst)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

