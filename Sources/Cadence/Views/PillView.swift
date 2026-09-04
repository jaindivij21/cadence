import SwiftUI

/// The quiet alert. One glass capsule that drops under the menu bar, says its
/// piece, and leaves. It is never on screen when it has nothing to ask.
struct PillView: View {
    let reminder: Reminder
    let progress: String?
    var onDone: () -> Void
    var onSnooze: () -> Void
    var onSkip: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.symbol)
                .font(.ui(14, .semibold))
                .foregroundStyle(reminder.category.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.name)
                    .font(.ui(14, .semibold))
                Text(progress ?? reminder.detail)
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 14)

            Button(reminder.actionLabel, action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(reminder.category.color)

            Button("\(reminder.snoozeMinutes)m", action: onSnooze)
                .buttonStyle(.bordered)

            Button {
                onSkip()
            } label: {
                Image(systemName: "xmark")
                    .font(.ui(10, .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .controlSize(.small)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 54)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: 560)
        .glassCapsule(interactive: false)
        // Room for the glass shadow, so the window does not clip it.
        .padding(14)
    }
}
