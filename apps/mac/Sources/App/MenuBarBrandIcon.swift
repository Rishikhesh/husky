import AppKit
import SwiftUI
import ThinkingOrbsKit

/// the menu bar icon is the persistent indicator the hud deliberately is
/// not (ADR 0040): your listening orb, in one colour like every menu bar
/// icon, wearing what `DictationCoordinator.badgeLook` says: a take, a
/// meeting's phase, a call nobody records or a setup gap.
@MainActor
enum MenuBarBrandIcon {
    static func image(for look: BadgeLook, orb: ListeningOrb, time: Double) -> NSImage {
        let image = BadgeMarks.image(for: look, orb: glyph(orb, time: time))
        image.accessibilityDescription = accessibilityDescription(for: look) ?? "Husky"
        return image
    }

    /// the engine's frame at `time`, from its preset tuned for small sizes.
    static func glyph(_ orb: ListeningOrb, time: Double) -> OrbGlyph {
        let frame = orbFrame(state: state(orb), size: .px20, t: time)
        return OrbGlyph(
            side: Double(OrbSize.px20.rawValue),
            dots: frame.dots.map {
                OrbGlyph.Dot(x: $0.x, y: $0.y, radius: $0.r, alpha: $0.a)
            },
            lines: frame.lines.map {
                OrbGlyph.Line(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2, width: $0.w, alpha: $0.a)
            }
        )
    }

    /// how fast this orb's engine clock runs against the wall clock.
    static func speed(_ orb: ListeningOrb) -> Double {
        resolvePreset(state(orb), .px20).speed
    }

    private static func state(_ orb: ListeningOrb) -> OrbState {
        OrbState(rawValue: orb.rawValue) ?? .composing
    }

    /// what VoiceOver hears for the image itself; the menu bar item's
    /// label says the state in words on top of this.
    private static func accessibilityDescription(
        for look: BadgeLook
    ) -> String? {
        switch look {
        case .idle: nil
        case .dictating: "Husky recording"
        case .callNotRecorded: "Husky, a call is on"
        // worn while a meeting gets ready and while one is written out:
        // the menu bar item's label says which.
        case .gettingReady: "Husky busy with a meeting"
        case .recordingMeeting: "Husky recording a meeting"
        case .meetingProblem: "Husky has a problem with the meeting"
        case .needsSetup: "Husky needs setup"
        }
    }
}

/// the menu bar item's image: a still frame of your orb, and a live one
/// while you talk.
struct MenuBarIcon: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject var settings: AppSettings
    @StateObject private var clock = MenuBarOrbClock()

    var body: some View {
        let look = coordinator.badgeLook
        Image(nsImage: MenuBarBrandIcon.image(
            for: look, orb: settings.listeningOrb, time: clock.time))
            .onChange(of: look == .dictating, initial: true) { _, live in
                clock.run(live, speed: MenuBarBrandIcon.speed(settings.listeningOrb))
            }
    }
}

/// the orb's clock in the menu bar: 15 frames a second while you talk,
/// nothing at all otherwise. it stops where it is, so the still frame
/// after a take is the last one you saw, never a jump. with Reduce Motion
/// it never runs.
@MainActor
final class MenuBarOrbClock: ObservableObject {
    /// a frame each orb shows well at rest.
    @Published private(set) var time: Double = 1.2

    private static let framesPerSecond: Double = 15
    private var timer: Timer?
    private var lastTick = Date()
    private var speed: Double = 1

    func run(_ live: Bool, speed: Double) {
        timer?.invalidate()
        timer = nil
        guard live, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        self.speed = speed
        lastTick = Date()
        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // .common, so it keeps going while the panel is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        // a stall (sleep, a busy main thread) is not a jump forward.
        time += min(now.timeIntervalSince(lastTick), 0.25) * speed
        lastTick = now
    }
}
