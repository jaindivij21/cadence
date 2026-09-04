import SwiftUI

/// The quiet alert: a card in the top-right that never steals focus.
struct ToastView: View {
    let reminder: Reminder
    var progressText: String? = nil
    var onDone: () -> Void
    var onSkip: () -> Void
    var onSnooze: () -> Void

    @State private var appeared = false

    private var accent: Color { reminder.category.color }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 11) {
                    ZStack {
                        Circle().fill(accent.opacity(0.15))
                        Image(systemName: reminder.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(reminder.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.textPrime)
                            if let progressText {
                                Text(progressText)
                                    .font(.cadenceMono)
                                    .foregroundStyle(accent)
                            }
                        }
                        Text(reminder.detail)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Palette.textSecond)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button(action: onSkip) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textFaint)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Skip this one")
                }

                HStack(spacing: 8) {
                    Button(action: onDone) {
                        Text(reminder.actionLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(accent.opacity(0.9))
                            )
                            .foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(.plain)

                    Button(action: onSnooze) {
                        Text("Snooze \(reminder.snoozeMinutes)m")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 1)
                            )
                            .foregroundStyle(Palette.textSecond)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
            .padding(14)
        }
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                Palette.surface.opacity(0.86)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(6)
        .scaleEffect(appeared ? 1 : 0.97)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true } }
    }
}
