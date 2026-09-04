import SwiftUI

/// The fallback alert, used only when the island is switched off. Same shape
/// language as the island's alert capsule, parked in the corner.
struct ToastView: View {
    let reminder: Reminder
    var progressText: String? = nil
    var onDone: () -> Void
    var onSkip: () -> Void
    var onSnooze: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reminder.symbol)
                .font(.ui(14, .semibold))
                .foregroundStyle(reminder.category.color)
                .frame(width: 34, height: 34)
                .glassCircle(tint: reminder.category.color.opacity(0.4))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(reminder.name)
                        .font(.ui(14, .semibold))
                    if let progressText {
                        Text(progressText)
                            .font(.ui(12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        onSkip()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.ui(10, .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text(reminder.detail)
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(reminder.actionLabel, action: onDone)
                        .buttonStyle(.borderedProminent)
                        .tint(reminder.category.color)
                    Button("Snooze \(reminder.snoozeMinutes)m", action: onSnooze)
                        .buttonStyle(.bordered)
                    Spacer(minLength: 0)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .glassSquircle(radius: 22)
        .padding(10)
    }
}
