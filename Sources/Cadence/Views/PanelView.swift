import AppKit
import SwiftUI

/// The menu bar panel. One glance should answer: what is next, how much water
/// is left, and what have I already done today.
struct PanelView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler
    @Environment(\.openWindow) private var openWindow

    @Environment(\.staticRender) private var staticRender

    private var stack: some View {
        VStack(spacing: 12) {
            nextUpCard
            if let water = waterReminder { hydration(water) }
            todayList
            weekStrip
        }
        .padding(12)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.hairline)

            MaybeScroll { stack }

            Divider().overlay(Palette.hairline)
            footer
        }
        .frame(width: 390)
        .frame(maxHeight: staticRender ? .infinity : 620)
        .background(Palette.ink)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Category.eye.color.opacity(0.15))
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Category.eye.color)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Cadence")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrime)
                Text(longDateString)
                    .font(.cadenceLabel)
                    .foregroundStyle(Palette.textFaint)
            }

            Spacer()

            if scheduler.isPaused {
                Button {
                    scheduler.resume()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        Text("Resume")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Palette.danger.opacity(0.18)))
                    .foregroundStyle(Palette.danger)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Button("Pause 15 minutes") { scheduler.pause(minutes: 15) }
                    Button("Pause 30 minutes") { scheduler.pause(minutes: 30) }
                    Button("Pause 1 hour") { scheduler.pause(minutes: 60) }
                    Button("Pause 3 hours") { scheduler.pause(minutes: 180) }
                } label: {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 15, weight: .regular))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
                .foregroundStyle(Palette.textSecond)
                .help("Pause reminders")
            }

            Button {
                openSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.textSecond)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Next up

    private var nextUpCard: some View {
        Group {
            if scheduler.isPaused, let until = scheduler.pausedUntil {
                pausedCard(until: until)
            } else if let next = scheduler.upcoming.first {
                let accent = next.reminder.category.color
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: next.reminder.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accent)
                        Text("NEXT UP")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(Palette.textFaint)
                        Spacer()
                        Text(clock(next.fireAt))
                            .font(.cadenceMono)
                            .foregroundStyle(Palette.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(countdown(to: next.fireAt))
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundStyle(Palette.textPrime)
                            .contentTransition(.numericText())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next.reminder.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.textPrime)
                            Text(next.reminder.schedule.summary)
                                .font(.cadenceLabel)
                                .foregroundStyle(Palette.textFaint)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                    HStack(spacing: 8) {
                        Button {
                            scheduler.triggerNow(next.reminder)
                        } label: {
                            Text("Start now")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.opacity(0.9)))
                                .foregroundStyle(Palette.ink)
                        }
                        .buttonStyle(.plain)

                        Button {
                            log(next.reminder, kind: .done)
                        } label: {
                            Text("Log it")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .frame(width: 78, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                                .foregroundStyle(Palette.textSecond)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                }
                .card(fill: Palette.surface)
            } else {
                emptyCard
            }
        }
    }

    private func pausedCard(until: Date) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Palette.danger.opacity(0.8))
            Text("Paused until \(clock(until))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrime)
            Text("Nothing will interrupt you.")
                .font(.cadenceLabel)
                .foregroundStyle(Palette.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Category.eye.color.opacity(0.8))
            Text("All clear for today")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrime)
            Text("Nothing else is scheduled inside your waking window.")
                .font(.cadenceLabel)
                .foregroundStyle(Palette.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .card()
    }

    // MARK: - Hydration

    private var waterReminder: Reminder? {
        store.config.reminders.first {
            $0.enabled && $0.category == .hydration && ($0.dailyTarget ?? 0) > 0
        }
    }

    private func hydration(_ reminder: Reminder) -> some View {
        let target = reminder.dailyTarget ?? 1
        let total = store.today.total(for: reminder.id)
        let fraction = min(1, total / target)
        let unit = reminder.unit ?? ""
        let accent = Category.hydration.color

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("HYDRATION")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Palette.textFaint)
                Spacer()
                Text(Fmt.amountString(total))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrime)
                Text("/ \(Fmt.amountString(target)) \(unit)")
                    .font(.cadenceLabel)
                    .foregroundStyle(Palette.textFaint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(LinearGradient(colors: [accent.opacity(0.6), accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * fraction))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                Button {
                    log(reminder, kind: .done)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                        Text("\(Fmt.amountString(reminder.amount ?? 0)) \(unit)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.opacity(0.16)))
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)

                Button {
                    store.undoLast(reminder)
                    scheduler.acknowledged(reminder)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                        .foregroundStyle(Palette.textSecond)
                }
                .buttonStyle(.plain)
                .help("Undo the last entry")

                Spacer()

                Text(remainingCopy(total: total, target: target, unit: unit))
                    .font(.cadenceLabel)
                    .foregroundStyle(Palette.textFaint)
            }
        }
        .padding(14)
        .card()
    }

    private func remainingCopy(total: Double, target: Double, unit: String) -> String {
        let left = max(0, target - total)
        if left == 0 { return "target hit" }
        return "\(Fmt.amountString(left)) \(unit) to go"
    }

    // MARK: - Today list

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Palette.textFaint)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ForEach(Array(store.config.reminders.enumerated()), id: \.element.id) { index, reminder in
                if reminder.enabled {
                    ReminderRow(
                        reminder: reminder,
                        done: store.today.doneCount(for: reminder.id),
                        target: slotTarget(reminder),
                        nextFire: scheduler.nextFire(for: reminder),
                        now: scheduler.now,
                        onLog: { log(reminder, kind: .done) }
                    )
                    if index < store.config.reminders.count - 1 {
                        Divider().overlay(Palette.hairline).padding(.leading, 46)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .card()
    }

    private func slotTarget(_ reminder: Reminder) -> Int? {
        switch reminder.schedule {
        case .everyMinutes: return nil
        case .timesPerDay(let n): return n
        case .atTimes(let t): return t.count
        }
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("LAST 7 DAYS")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Palette.textFaint)

            HStack(spacing: 6) {
                ForEach((0..<7).reversed(), id: \.self) { offset in
                    let score = adherence(offset: offset)
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Category.eye.color.opacity(offset == 0 ? 0.9 : 0.55))
                                .frame(height: max(3, 42 * score))
                        }
                        .frame(height: 42)
                        Text(weekdayLabel(offset: offset))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(offset == 0 ? Palette.textSecond : Palette.textFaint)
                    }
                }
            }
        }
        .padding(14)
        .card()
    }

    /// Share of answered reminders that were actually completed that day.
    private func adherence(offset: Int) -> Double {
        guard let day = store.day(offsetFromToday: offset), !day.events.isEmpty else { return 0 }
        let done = day.events.filter { $0.kind == .done }.count
        return Double(done) / Double(day.events.count)
    }

    private func weekdayLabel(offset: Int) -> String {
        guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return "" }
        return Fmt.weekdayInitial.string(from: date)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                openSettings()
            } label: {
                Text("Settings")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textSecond)
            }
            .buttonStyle(.plain)

            Button {
                NSWorkspace.shared.open(Store.directory)
            } label: {
                Text("Data folder")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textSecond)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                store.saveNow()
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textFaint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Helpers

    private func log(_ reminder: Reminder, kind: EventKind) {
        store.log(reminder, kind: kind)
        scheduler.acknowledged(reminder)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    private var longDateString: String { Fmt.longDate.string(from: Date()) }

    private func clock(_ date: Date) -> String { Fmt.clock.string(from: date) }

    private func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(scheduler.now)))
        if seconds >= 3600 {
            return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Formatters

/// Allocated once. The panel redraws every second, so building a DateFormatter
/// per row per tick is not free.
enum Fmt {
    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    static let longDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f
    }()
    static let weekdayInitial: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f
    }()
    static let amount: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func amountString(_ value: Double) -> String {
        amount.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
}

// MARK: - Row

private struct ReminderRow: View {
    let reminder: Reminder
    let done: Int
    let target: Int?
    let nextFire: Date?
    let now: Date
    var onLog: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(reminder.category.color.opacity(0.14))
                Image(systemName: reminder.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(reminder.category.color)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.name)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textPrime)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let target {
                        if target > 1 { pips(done: done, target: target) }
                        Text("\(done)/\(target)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textFaint)
                    } else {
                        Text(reminder.schedule.summary)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textFaint)
                    }
                }
            }

            Spacer(minLength: 4)

            if hovering {
                Button(action: onLog) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(reminder.category.color)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(reminder.category.color.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Mark done now")
            } else {
                Text(relativeNext)
                    .font(.cadenceMono)
                    .foregroundStyle(Palette.textFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func pips(done: Int, target: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(target, 12), id: \.self) { i in
                Circle()
                    .fill(i < done ? reminder.category.color : Color.white.opacity(0.12))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var relativeNext: String {
        guard let nextFire else {
            if let target, done < target { return "missed" }
            return "done"
        }
        let seconds = Int(nextFire.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        return Fmt.clock.string(from: nextFire)
    }
}
