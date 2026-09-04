import SwiftUI

/// The full-screen take-over. Deliberately almost empty: one instruction, one
/// countdown, and a way out. Nothing to read means nothing to keep staring at.
struct BreakOverlayView: View {
    @ObservedObject var session: AlertPresenter.BreakSession
    var onDone: () -> Void
    var onSkip: () -> Void

    @State private var breathe = false

    private var accent: Color { session.reminder.category.color }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .fullScreenUI)
                .ignoresSafeArea()

            Palette.ink.opacity(0.82).ignoresSafeArea()

            // A slow wash of the category colour behind everything.
            RadialGradient(
                colors: [accent.opacity(0.20), .clear],
                center: .center,
                startRadius: 40,
                endRadius: breathe ? 720 : 520
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: breathe)

            VStack(spacing: 40) {
                header
                dial
                copy
                controls
            }
            .padding(60)
        }
        .focusable()
        .onExitCommand { if session.canDismiss { onSkip() } }
        .onAppear { breathe = true }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: session.reminder.symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(session.reminder.name.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(2.4)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(accent.opacity(0.12))
        )
        .overlay(
            Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
    }

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 3)
                .frame(width: 260, height: 260)

            Circle()
                .fill(accent.opacity(0.06))
                .frame(width: breathe ? 250 : 200, height: breathe ? 250 : 200)
                .blur(radius: 20)
                .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: breathe)

            Circle()
                .trim(from: 0, to: session.progress)
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.5), accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 260, height: 260)
                .animation(.linear(duration: 1), value: session.progress)

            VStack(spacing: 2) {
                Text("\(max(0, session.remaining))")
                    .font(.cadenceDisplay)
                    .foregroundStyle(Palette.textPrime)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: session.remaining)
                Text("SECONDS")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Palette.textFaint)
            }
        }
    }

    private var copy: some View {
        Text(session.reminder.detail)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(Palette.textSecond)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .frame(maxWidth: 460)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Text(session.reminder.actionLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 150, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(session.canDismiss ? 0.9 : 0.25))
                    )
                    .foregroundStyle(session.canDismiss ? Palette.ink : Palette.textFaint)
            }
            .buttonStyle(.plain)
            .disabled(!session.canDismiss)
            .keyboardShortcut(.defaultAction)

            Button(action: onSkip) {
                Text("Skip")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(width: 92, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .foregroundStyle(session.canDismiss ? Palette.textSecond : Palette.textFaint.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!session.canDismiss)
        }
        .opacity(session.canDismiss ? 1 : 0.55)
        .animation(.easeOut(duration: 0.3), value: session.canDismiss)
    }
}
