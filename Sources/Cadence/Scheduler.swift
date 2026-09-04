import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Works out what is due and when the next thing lands. It never draws
/// anything — it hands a due reminder to `onDue` and lets the presenter decide
/// how loud to be.
@MainActor
final class Scheduler: ObservableObject {

    struct Upcoming: Identifiable {
        let reminder: Reminder
        let fireAt: Date
        var id: UUID { reminder.id }
    }

    /// Sorted soonest first. Reminders finished for the day are left out.
    @Published private(set) var upcoming: [Upcoming] = []
    @Published private(set) var now: Date = Date()
    @Published var pausedUntil: Date? {
        didSet { recompute() }
    }

    var onDue: ((Reminder) -> Void)?

    private let store: Store
    let presence = Presence()
    private var timer: Timer?

    /// Interval reminders count from here. Reset on launch, on completion, and
    /// whenever you have been away from the keyboard long enough that the break
    /// already happened.
    private var intervalAnchor: [UUID: Date] = [:]

    /// Reminders currently on screen or queued, so a slow tick cannot fire the
    /// same thing twice.
    private var inFlight: Set<UUID> = []

    init(store: Store) {
        self.store = store
        let launch = Date()
        for reminder in store.config.reminders where reminder.schedule.isInterval {
            intervalAnchor[reminder.id] = launch
        }

        presence.onReturn = { [weak self] away in
            self?.cameBack(after: away)
        }
        recompute()
    }

    /// The window every slot is spread across: learned from use when there is
    /// enough history, otherwise whatever is set by hand.
    var waking: TimeWindow {
        store.effectiveWaking
    }

    /// Screen off or locked, so the interval clocks hold rather than run.
    /// Coming back from a long absence counts as the break itself.
    private func cameBack(after away: TimeInterval) {
        for reminder in store.config.reminders {
            guard case .everyMinutes(let minutes) = reminder.schedule,
                  let anchor = intervalAnchor[reminder.id] else { continue }
            if away >= Double(minutes) * 60 {
                intervalAnchor[reminder.id] = now
            } else {
                intervalAnchor[reminder.id] = anchor.addingTimeInterval(away)
            }
        }
        recompute()
    }

    // MARK: - Lifecycle

    func start() {
        presence.start()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so countdowns keep running while a menu is open.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        presence.stop()
        timer?.invalidate()
        timer = nil
    }

    var isPaused: Bool {
        guard let until = pausedUntil else { return false }
        return until > Date()
    }

    func pause(minutes: Int) {
        pausedUntil = Date().addingTimeInterval(Double(minutes) * 60)
    }

    func resume() { pausedUntil = nil }

    // MARK: - Reporting completion back

    /// Call after the user answers a reminder, so intervals restart and slot
    /// counts advance.
    func acknowledged(_ reminder: Reminder) {
        inFlight.remove(reminder.id)
        intervalAnchor[reminder.id] = Date()
        // Any full-screen break rests the eyes, so the 20-20-20 clock restarts too.
        if reminder.alert.isBlocking {
            for other in store.config.reminders
            where other.id != reminder.id && other.category == .eye && other.schedule.isInterval {
                intervalAnchor[other.id] = Date()
            }
        }
        recompute()
    }

    func snoozed(_ reminder: Reminder, minutes: Int) {
        inFlight.remove(reminder.id)
        // Push the interval anchor forward so the next fire is `minutes` away.
        if case .everyMinutes(let m) = reminder.schedule {
            intervalAnchor[reminder.id] = Date().addingTimeInterval(Double(minutes - m) * 60)
        } else {
            snoozedSlots[reminder.id] = Date().addingTimeInterval(Double(minutes) * 60)
        }
        recompute()
    }

    private var snoozedSlots: [UUID: Date] = [:]

    // MARK: - The tick

    private func tick() {
        now = Date()
        store.ensureToday()
        guard presence.isPresent else {
            // Away: the clocks hold and nothing fires at an empty chair.
            return
        }
        store.noteSeen(now)
        writeOffStaleSlots()
        recompute()
        fireDueReminders()
    }


    /// A slot that is more than the grace period late is recorded as missed and
    /// skipped, rather than ambushing you three hours after the fact.
    private func writeOffStaleSlots() {
        let grace = Double(store.config.slotGraceMinutes) * 60
        for reminder in store.config.reminders where reminder.enabled && !reminder.schedule.isInterval {
            let slots = reminder.slots(global: waking)
            guard !slots.isEmpty else { continue }
            var handled = store.today.handledCount(for: reminder.id)
            while handled < slots.count,
                  let slotDate = date(forMinute: slots[handled]),
                  now.timeIntervalSince(slotDate) > grace {
                store.log(reminder, kind: .missed, at: slotDate)
                handled += 1
            }
        }
    }

    private func fireDueReminders() {
        guard !isPaused else { return }
        for item in upcoming where item.fireAt <= now && !inFlight.contains(item.reminder.id) {
            inFlight.insert(item.reminder.id)
            onDue?(item.reminder)
        }
    }

    /// Clears a reminder that was dismissed without an explicit answer.
    func released(_ reminderID: UUID) {
        inFlight.remove(reminderID)
    }

    // MARK: - Next-fire maths

    func date(forMinute minute: MinuteOfDay, on day: Date = Date()) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        return cal.date(byAdding: .minute, value: minute, to: start)
    }

    private func minuteOfDay(_ date: Date) -> MinuteOfDay {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// When this reminder fires next, or nil if it is finished for the day.
    func nextFire(for reminder: Reminder) -> Date? {
        guard reminder.enabled else { return nil }
        let window = reminder.activeWindow(global: waking)

        switch reminder.schedule {
        case .everyMinutes(let minutes):
            let anchor = intervalAnchor[reminder.id] ?? now
            var candidate = anchor.addingTimeInterval(Double(minutes) * 60)
            // Hold anything that lands outside the window until the window opens.
            if let windowStart = date(forMinute: window.start),
               let windowEnd = date(forMinute: window.end) {
                if candidate < windowStart { candidate = windowStart }
                if candidate > windowEnd {
                    guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                          let next = date(forMinute: window.start, on: tomorrow) else { return nil }
                    candidate = next
                }
            }
            return candidate

        case .timesPerDay, .atTimes:
            let slots = reminder.slots(global: waking)
            let handled = store.today.handledCount(for: reminder.id)
            guard handled < slots.count else { return nil }
            guard var fire = date(forMinute: slots[handled]) else { return nil }
            if let snooze = snoozedSlots[reminder.id], snooze > fire { fire = snooze }
            return fire
        }
    }

    private func recompute() {
        var list: [Upcoming] = []
        for reminder in store.config.reminders where reminder.enabled {
            if let fire = nextFire(for: reminder) {
                list.append(Upcoming(reminder: reminder, fireAt: fire))
            }
        }
        upcoming = list.sorted { $0.fireAt < $1.fireAt }
    }

    /// Fire a reminder right now, from the panel.
    func triggerNow(_ reminder: Reminder) {
        guard !inFlight.contains(reminder.id) else { return }
        inFlight.insert(reminder.id)
        onDue?(reminder)
    }
}

extension Schedule {
    var isInterval: Bool {
        if case .everyMinutes = self { return true }
        return false
    }
}
