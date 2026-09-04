import SwiftUI

/// The full-screen take-over. Your desktop, frosted, with one instruction and a
/// countdown floating on it. Deliberately almost empty — nothing to read means
/// nothing to keep staring at.
struct BreakOverlayView: View {
    @ObservedObject var session: AlertPresenter.BreakSession
    var onDone: () -> Void
    var onSkip: () -> Void
    var onCompanion: (Reminder) -> Void

    private var accent: Color { session.reminder.category.color }

    var body: some View {
        ZStack {
            // `.thickMaterial` here would be a flat grey sheet: a SwiftUI
            // Material blurs within its own window, and this window is empty.
            // Only a behind-window effect view actually frosts the desktop.
            Backdrop(material: .fullScreenUI)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                name
                dial
                instruction
                controls
                if !session.companions.isEmpty { companions }
            }
            .padding(60)
        }
        .focusable()
        .onExitCommand { if session.canDismiss { onSkip() } }
    }

    private var name: some View {
        HStack(spacing: 8) {
            Image(systemName: session.reminder.symbol)
                .font(.ui(13, .semibold))
            Text(session.reminder.name)
                .font(.ui(15, .medium))
        }
        .foregroundStyle(.secondary)
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

            Text("\(max(0, session.remaining))")
                .font(.system(size: 84, weight: .thin, design: .default))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: session.remaining)
        }
        .frame(width: 236, height: 236)
        .animation(.linear(duration: 1), value: session.progress)
    }

    private var instruction: some View {
        Text(session.reminder.detail)
            .font(.system(size: 26, weight: .light))
            .multilineTextAlignment(.center)
            .lineSpacing(6)
            .frame(maxWidth: 560)
    }

    /// You are already standing here with your eyes shut. Anything else falling
    /// due in the next few minutes may as well happen now, rather than pulling
    /// you out of your work again a minute later.
    private var companions: some View {
        VStack(spacing: 14) {
            Text(companionHeading)
                .font(.ui(12))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(session.companions) { companion in
                    let taken = session.answeredCompanions.contains(companion.id)
                    Button {
                        onCompanion(companion)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: taken ? "checkmark" : companion.symbol)
                                .font(.ui(11, .semibold))
                            Text(companion.name)
                                .font(.ui(13))
                        }
                        .foregroundStyle(taken ? AnyShapeStyle(.secondary) : AnyShapeStyle(companion.category.color))
                    }
                    .buttonStyle(.glass)
                    .disabled(taken)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: session.answeredCompanions)
    }

    /// Several drops at one stop need spacing, or the second washes the first
    /// straight out.
    private var companionHeading: String {
        let drops = session.companions.filter { $0.alert.isBlocking && $0.category == .eye }
        if drops.isEmpty { return "While you're here" }
        return "Also now — leave about five minutes between each"
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(session.reminder.actionLabel, action: onDone)
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
    }
}
