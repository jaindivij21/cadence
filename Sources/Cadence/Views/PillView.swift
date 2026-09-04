import SwiftUI

/// The quiet alert. One glass capsule that drops under the menu bar, says its
/// piece, and leaves. It is never on screen when it has nothing to ask.
///
/// The width is fixed on purpose. An earlier version let the capsule size to
/// its contents, and a reminder with a long detail line stretched it clean off
/// the screen. A pill is a pill; the text truncates to fit it, and the full
/// wording lives in Settings and on the break screen.
struct PillView: View {
    let reminder: Reminder
    let progress: String?
    var companions: [Reminder] = []
    var answeredCompanions: Set<UUID> = []
    var onDone: () -> Void
    var onSnooze: () -> Void
    var onSkip: () -> Void
    var onCompanion: (Reminder) -> Void = { _ in }

    /// Two chips at most, or the actions get squeezed out.
    private var shownCompanions: [Reminder] { Array(companions.prefix(2)) }

    private var width: CGFloat { 560 }

    /// One line covering the whole stop. The single Done answers for all of it,
    /// so there is nothing to tick off separately.
    private var line: String {
        let base = progress ?? reminder.detail
        guard !shownCompanions.isEmpty else { return base }
        return base + "  ·  Also: " + shownCompanions.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: reminder.symbol)
                .font(.ui(15, .semibold))
                .foregroundStyle(reminder.category.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.name)
                    .font(.ui(14, .semibold))
                    .lineLimit(1)
                // Scrolls itself when the sentence is longer than the pill, and
                // stays still when it is not.
                MarqueeText(text: progress ?? reminder.detail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDone) {
                HStack(spacing: 6) {
                    Text(shownCompanions.isEmpty ? reminder.actionLabel : "Done with all")
                    Text("space")
                        .font(.ui(9, .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(.black.opacity(0.18))
                        )
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(reminder.category.color)
            .fixedSize()

            Button("\(reminder.snoozeMinutes)m", action: onSnooze)
                .buttonStyle(.bordered)
                .fixedSize()

            Button {
                onSkip()
            } label: {
                Image(systemName: "xmark")
                    .font(.ui(10, .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .controlSize(.small)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(width: width, height: 58)
        .glassCapsule(interactive: false)
        // Room for the glass shadow, so the window does not clip it.
        .padding(16)
    }
}
