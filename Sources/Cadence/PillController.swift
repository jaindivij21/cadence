import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// Holds which companions have been ticked, so the pill can grey them out
/// without the controller having to rebuild the whole view.
private struct PillHost: View {
    let reminder: Reminder
    let progress: String?
    let companions: [Reminder]
    let onDone: () -> Void
    let onSnooze: () -> Void
    let onSkip: () -> Void
    let onCompanion: (Reminder) -> Void

    @State private var answered: Set<UUID> = []

    var body: some View {
        PillView(
            reminder: reminder,
            progress: progress,
            companions: companions,
            answeredCompanions: answered,
            onDone: onDone,
            onSnooze: onSnooze,
            onSkip: onSkip,
            onCompanion: { companion in
                answered.insert(companion.id)
                onCompanion(companion)
            }
        )
    }
}

/// Owns the transient alert pill: a borderless panel that drops in under the
/// menu bar when something is due and is torn down the moment it is answered.
///
/// It is deliberately not a persistent window. An earlier version parked a
/// permanent island on the desktop, which is exactly the thing a reminder app
/// must not do — it becomes furniture, and then it is in the way.
@MainActor
final class PillController {
    private var panel: NSPanel?

    /// Space answers the pill without reaching for the mouse.
    ///
    /// The pill never takes focus, by design — a reminder must not yank your
    /// cursor out of what you are writing. So the only way to hear a bare
    /// spacebar is to claim it system-wide, and a claimed space is a space that
    /// never reaches your document.
    ///
    /// The compromise: claim it only while you are demonstrably not typing.
    /// This polls the keyboard's idle time and holds the key only after a few
    /// quiet seconds, releasing it within a second of you starting to type
    /// again. Hit space mid-sentence and it goes where you meant it to.
    private let spaceKey = HotKey(identifier: 2)
    private var spaceWatchdog: Timer?
    private var confirm: (() -> Void)?
    /// Seconds of no typing before space belongs to the pill.
    private let quietBeforeClaiming: Double = 3

    var isShowing: Bool { panel != nil }

    func show(
        _ reminder: Reminder,
        progress: String?,
        companions: [Reminder] = [],
        onDone: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onCompanion: @escaping (Reminder) -> Void = { _ in }
    ) {
        hide()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 82),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // the glass carries its own
        // Above everything, on every space, including over a full-screen app.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = PillHost(
            reminder: reminder,
            progress: progress,
            companions: companions,
            onDone: onDone,
            onSnooze: onSnooze,
            onSkip: onSkip,
            onCompanion: onCompanion
        )
        .measure { [weak panel] size in
            guard let panel, size.width > 1, size.height > 1 else { return }
            guard abs(panel.frame.width - size.width) > 0.5 || abs(panel.frame.height - size.height) > 0.5 else { return }
            PillController.place(panel, size: size)
        }

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        PillController.place(panel, size: panel.frame.size)
        self.panel = panel
        confirm = onDone
        startWatchingForQuiet()

        // Drop in from just above its resting place.
        let resting = panel.frame
        panel.setFrameOrigin(NSPoint(x: resting.minX, y: resting.minY + 14))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(resting.origin)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        stopWatchingForQuiet()
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX, y: panel.frame.minY + 10))
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    // MARK: - Spacebar

    private func startWatchingForQuiet() {
        stopWatchingForQuiet()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconsiderSpace() }
        }
        RunLoop.main.add(timer, forMode: .common)
        spaceWatchdog = timer
        reconsiderSpace()
    }

    private func stopWatchingForQuiet() {
        spaceWatchdog?.invalidate()
        spaceWatchdog = nil
        spaceKey.unregister()
        confirm = nil
    }

    private func reconsiderSpace() {
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let quiet = idle >= quietBeforeClaiming

        if quiet, !spaceKey.isRegistered {
            spaceKey.register(keyCode: UInt32(kVK_Space), modifiers: 0) { [weak self] in
                self?.confirm?()
            }
        } else if !quiet, spaceKey.isRegistered {
            spaceKey.unregister()
        }
    }

    /// Centred at the top of the active screen, just below the menu bar, where
    /// macOS itself puts transient status.
    private static func place(_ panel: NSPanel, size: CGSize) {
        guard let screen = NSScreen.active else { return }
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.maxY - size.height).rounded(),
                width: size.width.rounded(),
                height: size.height.rounded()
            ),
            display: true
        )
    }
}
