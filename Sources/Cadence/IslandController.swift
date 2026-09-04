import AppKit
import SwiftUI

/// Owns the floating island window: a borderless, non-activating panel that
/// sits above the desktop, resizes itself to whatever shape the island is
/// currently in, and remembers where you dragged it.
@MainActor
final class IslandController {
    let model = IslandModel()

    private var panel: NSPanel?
    private let store: Store
    private let scheduler: Scheduler
    private var onAnswer: (Reminder, EventKind) -> Void = { _, _ in }
    private var onSnooze: (Reminder) -> Void = { _ in }
    private var onOpenSettings: () -> Void = {}
    private var moveObserver: NSObjectProtocol?

    init(store: Store, scheduler: Scheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    func configure(
        onAnswer: @escaping (Reminder, EventKind) -> Void,
        onSnooze: @escaping (Reminder) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onAnswer = onAnswer
        self.onSnooze = onSnooze
        self.onOpenSettings = onOpenSettings
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Showing and hiding

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false            // the glass draws its own
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = IslandView(
            model: model,
            onAnswer: { [weak self] reminder, kind in self?.onAnswer(reminder, kind) },
            onSnooze: { [weak self] reminder in self?.onSnooze(reminder) },
            onOpenSettings: { [weak self] in self?.onOpenSettings() }
        )
        .environmentObject(store)
        .environmentObject(scheduler)
        .measure { [weak self] size in
            self?.resize(to: size)
        }

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []          // the panel is sized from `measure`
        panel.contentView = hosting
        self.panel = panel

        place(panel)
        panel.orderFrontRegardless()

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rememberPosition() }
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Follows the `showIsland` setting and steps out of the way while a
    /// full-screen break is up.
    func sync(suppressed: Bool) {
        if store.config.showIsland && !suppressed {
            show()
        } else if suppressed {
            hide()
        } else {
            close()
        }
    }

    // MARK: - Geometry

    /// Grows and shrinks around its own centre, so expanding on hover does not
    /// shove the capsule out from under the pointer.
    private func resize(to size: CGSize) {
        guard let panel, size.width > 1, size.height > 1 else { return }
        let current = panel.frame
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }

        let centre = NSPoint(x: current.midX, y: current.midY)
        let frame = NSRect(
            x: (centre.x - size.width / 2).rounded(),
            y: (centre.y - size.height / 2).rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
        panel.setFrame(frame, display: true, animate: false)
    }

    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size

        if let stored = store.config.islandCenter, stored.count == 2 {
            let centre = NSPoint(x: stored[0], y: stored[1])
            // Only trust a stored position that is still on a screen.
            if NSScreen.screens.contains(where: { $0.frame.contains(centre) }) {
                panel.setFrameOrigin(NSPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2))
                return
            }
        }

        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 90
        ))
    }

    private func rememberPosition() {
        guard let panel else { return }
        store.config.islandCenter = [panel.frame.midX, panel.frame.midY]
    }

    // MARK: - Alerts

    /// Presents a reminder inside the island. Returns false when the island is
    /// not on screen, so the caller can fall back to the corner card.
    func present(_ reminder: Reminder, progress: String?) -> Bool {
        guard isVisible else { return false }
        model.alertProgress = progress
        model.alert = reminder
        return true
    }

    func dismissAlert() {
        model.alert = nil
        model.alertProgress = nil
    }

    var showingAlert: Bool { model.alert != nil }
}
