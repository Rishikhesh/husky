import SwiftUI

/// the settings window's sidebar, in the order it is read: home first,
/// general last, the way System Settings keeps its housekeeping at the end.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case dictation
    case listening
    case ai
    case meetings
    case dictionary
    case history
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .dictation: "Dictation"
        case .listening: "Listening"
        case .ai: "AI"
        case .meetings: "Meetings"
        case .dictionary: "Dictionary"
        case .history: "History"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .dictation: "waveform"
        case .listening: "circle.dotted"
        case .ai: "sparkles"
        case .meetings: "person.2.wave.2"
        case .dictionary: "character.book.closed"
        case .history: "clock.arrow.circlepath"
        case .general: "gearshape"
        }
    }

    /// the tile behind the symbol, as System Settings colours its rows.
    var tileColor: Color {
        switch self {
        case .home: .indigo
        case .dictation: .orange
        case .listening: .purple
        case .ai: .blue
        case .meetings: .green
        case .dictionary: .pink
        case .history: .teal
        case .general: .gray
        }
    }

    /// the one line under the pane's title: what the section is for.
    var blurb: String {
        switch self {
        case .home: "Your words today, and how fast they land."
        case .dictation: "Hold a key, talk, let go. Choose the key, the cleanup and the speech model."
        case .listening: "The orb that shows Husky hears you. It grows with your voice."
        case .ai: "Rewrite as you dictate and summarize meetings, with the provider you pick."
        case .meetings: "Record calls on this Mac and save transcripts where you want them."
        case .dictionary: "Words Husky should always get right."
        case .history: "Everything you have dictated and recorded, searchable."
        case .general: "Startup, updates and the version you are running."
        }
    }

    /// a little air above this row in the sidebar: home stands alone, the
    /// meetings end the doing, general is housekeeping.
    var startsGroup: Bool {
        self == .dictation || self == .dictionary || self == .general
    }
}

/// the dictation key may never be one the meeting shortcut holds: every
/// press of the shortcut would start a take too. checked where the key is
/// set, so no menu can let it through.
enum DictationKeyGuard {
    static func canBind(_ key: HotkeyBinding, meetingShortcut: MeetingShortcut?) -> Bool {
        meetingShortcut?.refusal(againstDictationKey: key) == nil
    }
}
