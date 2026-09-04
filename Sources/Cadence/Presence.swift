import AppKit
import CoreGraphics
import Foundation

/// Whether you are actually at the Mac.
///
/// An earlier version used keyboard idle time, which was wrong: reading a long
/// page, watching something, or thinking with your hands off the keys all look
/// identical to being away — and those are exactly the moments your eyes have
/// been fixed at one distance the longest. The honest signal is the screen. If
/// the display is on and the session is unlocked, you are looking at it.
///
/// None of this needs a permission: `CGDisplayIsAsleep` and the session
/// dictionary are readable by any process.
@MainActor
final class Presence: ObservableObject {

    @Published private(set) var isPresent: Bool = true

    /// Called when you come back, with how long the screen was off or locked.
    var onReturn: ((TimeInterval) -> Void)?

    private var awaySince: Date?
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let present = Presence.readIsPresent()
        guard present != isPresent else { return }

        if present {
            let away = awaySince.map { Date().timeIntervalSince($0) } ?? 0
            awaySince = nil
            isPresent = true
            onReturn?(away)
        } else {
            awaySince = Date()
            isPresent = false
        }
    }

    /// Screen on, session unlocked, and this session owns the console.
    static func readIsPresent() -> Bool {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return false }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool, locked { return false }
        if let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool, !onConsole { return false }
        return true
    }
}
