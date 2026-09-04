import AppKit
import SwiftUI

/// The menu bar popover. A short answer to "what is next and what have I done
/// today" — the island carries the moment-to-moment readout, so this stays a
/// list rather than a dashboard.
struct PanelView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler
    @Environment(\.staticRender) private var staticRender

    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if let water = waterReminder {
                hydration(water)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            Divider()

            MaybeScroll {
                VStack(spacing: 0) {
                    ForEach(store.config.reminders.filter(\.enabled)) { reminder in
                        row(reminder)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: staticRender ? nil : 300)

            Divider()

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if scheduler.isPaused, let until = scheduler.pausedUntil {
                    Text("Paused")
                        .font(.ui(22, .semibold))
                    Text("until \(Fmt.clock.string(from: until))")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                } else if let next = scheduler.upcoming.first {
                    Text(countdown(to: next.fireAt))
                        .font(.ui(22, .semibold))
                        .contentTransition(.numericText())
                    Text(next.reminder.name)
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("All clear")
                        .font(.ui(22, .semibold))
                    Text("Nothing left inside your waking window")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if scheduler.isPaused {
                Button("Resume") { scheduler.resume() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Menu {
                    Button("15 minutes") { scheduler.pause(minutes: 15) }
                    Button("30 minutes") { scheduler.pause(minutes: 30) }
                    Button("1 hour") { scheduler.pause(minutes: 60) }
                    Button("3 hours") { scheduler.pause(minutes: 180) }
                } label: {
                    Label("Pause", systemImage: "pause")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    // MARK: - Hydration

    private var waterReminder: Reminder? {
        store.config.reminders.first {
            $0.enabled && ($0.dailyTarget ?? 0) > 0 && $0.amount != nil
        }
    }

    private func hydration(_ reminder: Reminder) -> some View {
        let target = reminder.dailyTarget ?? 1
        let total = store.today.total(for: reminder.id)
        let unit = reminder.unit ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: min(1, total / target)) {
                HStack {
                    Text(reminder.name)
                        .font(.ui(12, .medium))
                    Spacer()
                    Text("\(Fmt.amountString(total)) / \(Fmt.amountString(target)) \(unit)")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .tint(reminder.category.color)

            HStack(spacing: 8) {
                Button("Add \(Fmt.amountString(reminder.amount ?? 0)) \(unit)", systemImage: "plus") {
                    log(reminder)
                }
                .buttonStyle(.bordered)

                Button("Undo", systemImage: "arrow.uturn.backward") {
                    store.undoLast(reminder)
                    scheduler.acknowledged(reminder)
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
            }
            .controlSize(.small)
        }
    }

    // MARK: - Rows

    private func row(_ reminder: Reminder) -> some View {
        let target = slotTarget(reminder)
        let done = store.today.takenCount(for: reminder.id)

        return HStack(spacing: 10) {
            Image(systemName: reminder.symbol)
                .font(.ui(12, .semibold))
                .foregroundStyle(reminder.category.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.name)
                    .font(.rowTitle)
                    .lineLimit(1)
                Text(target.map { "\(done) of \($0) today" } ?? reminder.schedule.summary)
                    .font(.rowMinor)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Text(nextLabel(reminder, done: done, target: target))
                .font(.ui(11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button {
                log(reminder)
            } label: {
                Image(systemName: "checkmark")
                    .font(.ui(10, .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(reminder.category.color)
            .help("Log one now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func nextLabel(_ reminder: Reminder, done: Int, target: Int?) -> String {
        guard let fire = scheduler.nextFire(for: reminder) else {
            if let target, done < target { return "missed" }
            return "done"
        }
        let seconds = Int(fire.timeIntervalSince(scheduler.now))
        if seconds <= 0 {
            // Due, but waiting out the quiet stretch after the last one.
            if let held = scheduler.heldUntil, held > scheduler.now {
                return "in \(max(1, Int(held.timeIntervalSince(scheduler.now)) / 60))m"
            }
            return "now"
        }
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        return Fmt.clock.string(from: fire)
    }

    private func slotTarget(_ reminder: Reminder) -> Int? {
        switch reminder.schedule {
        case .everyMinutes:       return nil
        case .timesPerDay(let n): return n
        case .atTimes(let t):     return t.count
        case .beforeEnd:          return 1
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Settings…", action: onOpenSettings)
                .buttonStyle(.plain)
                .font(.ui(12))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                store.saveNow()
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.ui(12))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func log(_ reminder: Reminder) {
        store.log(reminder, kind: .done)
        scheduler.acknowledged(reminder)
    }

    private func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(scheduler.now)))
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return String(format: "%d h %02d", seconds / 3600, (seconds % 3600) / 60)
    }
}
