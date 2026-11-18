import SwiftUI
import ThinkingOrbsKit

// the settings window's own pieces, drawn with the shared look
// (`AppLook.swift`): the sidebar's rows and its top card, each pane's hero,
// and the centred column a pane's form runs in.

extension SectionHero {
    init(_ section: SettingsSection) {
        self.init(symbol: section.symbol, tint: section.tileColor, title: section.title, blurb: section.blurb)
    }
}

/// how wide a pane's content runs before it centres instead of stretching.
enum SettingsLayout {
    static let column: CGFloat = 660
}

/// a pane's grouped form: see-through to the window's glass and glow, its
/// column centred and no wider than `SettingsLayout.column`. the margins go
/// on the scroll content, so the whole pane still scrolls from anywhere.
private struct SettingsFormColumn: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(
                .horizontal,
                max(24, (width - SettingsLayout.column) / 2),
                for: .scrollContent
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    func settingsForm() -> some View {
        modifier(SettingsFormColumn())
    }
}

/// a sidebar row: the symbol on its coloured tile, then the title.
struct SettingsSectionLabel: View {
    let section: SettingsSection

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            IconTile(symbol: section.symbol, tint: section.tileColor, size: 24)
        }
        .labelStyle(SidebarLabelStyle())
    }
}

/// tile and title a fixed ten points apart, centred on each other.
private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
            configuration.title
        }
    }
}

/// one sidebar row: a solid pill in the Mac's accent when it is where you
/// are, a faint fill under the pointer otherwise.
struct SettingsSidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let issueCount: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                SettingsSectionLabel(section: section)
                    .font(.system(size: 13.5))
                Spacer(minLength: 4)
                if issueCount > 0 {
                    Text("\(issueCount)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.red))
                        .accessibilityLabel("\(issueCount) setup \(issueCount == 1 ? "issue" : "issues")")
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(AppLook.accent) : AnyShapeStyle(.primary.opacity(hovering ? 0.06 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// the top of the sidebar: your orb, live, and whether Husky is ready to
/// hear you, or what is stopping it.
struct SettingsSidebarIdentity: View {
    let orb: ListeningOrb
    let key: String
    let setupFinished: Bool

    var body: some View {
        HStack(spacing: 10) {
            ThinkingOrb(
                state: OrbState(rawValue: orb.rawValue) ?? .composing,
                theme: .auto,
                displaySize: 34
            )
            // a still frame: it is on screen the whole time settings is
            // open, and a live one there kept the window redrawing.
            .orbFrozenTime(1.2)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Husky")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(setupFinished ? .green : .red)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(setupFinished ? "Ready · hold \(key)" : "Setup isn’t finished")
                        .lineLimit(1)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
