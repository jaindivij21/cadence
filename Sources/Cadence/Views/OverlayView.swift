import SwiftUI

/// The full-screen take-over. Your desktop, frosted, with one instruction and a
/// countdown on it.
///
/// When several screen-holding reminders fall due together it becomes a
/// sequence rather than three separate ambushes: each step holds for its own
/// duration, which is also the gap before the next one, and the whole stop is
/// confirmed once at the end.
struct BreakOverlayView: View {
    @ObservedObject var session: AlertPresenter.BreakSession
    var onDone: () -> Void
    var onSkip: () -> Void

    private var accent: Color { session.current.category.color }
    private var isSequence: Bool { session.steps.count > 1 }

    var body: some View {
        ZStack {
            // A SwiftUI Material blurs within its own window, and this window is
            // empty; only a behind-window effect view frosts the desktop.
            Backdrop(material: .fullScreenUI)
                .ignoresSafeArea()

            VStack(spacing: 38) {
                heading
                dial
                instruction
                if isSequence { queue }
                if !session.extras.isEmpty { extras }
                controls
            }
            .padding(60)
            .animation(.smooth(duration: 0.3), value: session.stepIndex)
        }
        .focusable()
        .onExitCommand { if session.canDismiss { onSkip() } }
    }

    // MARK: - Pieces

    private var heading: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: session.current.symbol)
                    .font(.ui(13, .semibold))
                Text(session.current.name)
                    .font(.ui(15, .medium))
            }
            .foregroundStyle(.secondary)

            if isSequence {
                Text("Step \(session.stepIndex + 1) of \(session.steps.count)")
                    .font(.ui(12))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var dial: some View {
        ZStack {
            ProgressRing(
                progress: session.progress,
                tint: accent,
                lineWidth: 3,
                track: Color.primary.opacity(0.08)
            )
            .frame(width: 236, height: 236)

            VStack(spacing: 2) {
                Text(clock)
                    .font(.system(size: 76, weight: .thin))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: session.remaining)
                if isSequence && !session.isLastStep {
                    Text("then \(session.steps[session.stepIndex + 1].name)")
                        .font(.ui(12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 236, height: 236)
        .animation(.linear(duration: 1), value: session.progress)
    }

    /// Minutes and seconds once a hold runs past a minute — a bare "174" means
    /// nothing to anyone.
    private var clock: String {
        let seconds = max(0, session.remaining)
        if seconds < 60 { return "\(seconds)" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var instruction: some View {
        Text(session.current.detail)
            .font(.system(size: 24, weight: .light))
            .multilineTextAlignment(.center)
            .lineSpacing(6)
            .frame(maxWidth: 560)
    }

    private var queue: some View {
        HStack(spacing: 10) {
            ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                let done = index < session.stepIndex
                let now = index == session.stepIndex
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark" : step.symbol)
                        .font(.ui(10, .semibold))
                    Text(step.name)
                        .font(.ui(12))
                }
                .foregroundStyle(now ? AnyShapeStyle(step.category.color)
                                     : AnyShapeStyle(done ? .tertiary : .secondary))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule().fill(now ? step.category.color.opacity(0.16) : .clear)
                )
                .overlay(
                    Capsule().strokeBorder(now ? .clear : Color.primary.opacity(0.10), lineWidth: 1)
                )
            }
        }
    }

    private var extras: some View {
        Text("Also now — \(session.extras.map(\.name).joined(separator: ", "))")
            .font(.ui(12))
            .foregroundStyle(.secondary)
    }

    /// One answer for the whole stop. Nothing to tick off item by item.
    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(doneLabel, action: onDone)
                    .buttonStyle(.glassProminent)
                    .tint(accent)
                    .keyboardShortcut(.defaultAction)

                Button("Skip", action: onSkip)
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
            .disabled(!session.canDismiss)
            .opacity(session.canDismiss ? 1 : 0.4)
            .animation(.easeOut(duration: 0.3), value: session.canDismiss)

            if session.allReminders.count > 1 {
                Text("Covers all \(session.allReminders.count)")
                    .font(.ui(11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var doneLabel: String {
        session.allReminders.count > 1 ? "Done with all" : session.current.actionLabel
    }
}
