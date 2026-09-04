import Foundation
import SwiftUI

/// Single source of truth: configuration plus the rolling log of what you
/// actually did. Everything is a plain JSON file under Application Support, so
/// nothing leaves the machine and you can read or edit it by hand.
@MainActor
final class Store: ObservableObject {

    @Published var config: Config {
        didSet { scheduleSave() }
    }

    /// Newest first. Trimmed to `historyDays`.
    @Published private(set) var days: [DayLog] {
        didSet { scheduleSave() }
    }

    private let historyDays = 30
    private var saveWorkItem: DispatchWorkItem?

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cadence", isDirectory: true)
    }()

    static var stateURL: URL { directory.appendingPathComponent("state.json") }

    private struct Persisted: Codable {
        var config: Config
        var days: [DayLog]
    }

    init() {
        let loaded = Store.load()
        config = loaded?.config ?? Config()
        days = loaded?.days ?? []
        ensureToday()
    }

    // MARK: - Loading and saving

    private static func load() -> Persisted? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Persisted.self, from: data)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func saveNow() {
        let payload = Persisted(config: config, days: days)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: Store.directory, withIntermediateDirectories: true)
            let data = try encoder.encode(payload)
            try data.write(to: Store.stateURL, options: .atomic)
        } catch {
            NSLog("Cadence: could not save state — \(error.localizedDescription)")
        }
    }

    // MARK: - Day handling

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }

    /// Makes sure a log for today exists and old ones are trimmed. Safe to call
    /// on every tick — it only writes when the day actually rolls over.
    func ensureToday() {
        let key = Store.dayKey()
        if days.first?.day == key { return }
        if let existing = days.firstIndex(where: { $0.day == key }) {
            let day = days.remove(at: existing)
            days.insert(day, at: 0)
        } else {
            days.insert(DayLog(day: key), at: 0)
        }
        if days.count > historyDays { days.removeSubrange(historyDays...) }
    }

    var today: DayLog {
        days.first ?? DayLog(day: Store.dayKey())
    }

    func day(offsetFromToday offset: Int) -> DayLog? {
        guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
        let key = Store.dayFormatter.string(from: date)
        return days.first { $0.day == key }
    }

    /// Records that the Mac was in use at this moment, which is what the
    /// learned waking window is built from.
    func noteSeen(_ date: Date) {
        ensureToday()
        guard !days.isEmpty else { return }
        if days[0].firstSeen == nil { days[0].firstSeen = date }
        let bucket = Store.minuteOfDay(date) / 15
        if !days[0].activeBuckets.contains(bucket) { days[0].activeBuckets.append(bucket) }
        // Only write when the minute changes, so this does not thrash the file.
        if let last = days[0].lastSeen, Int(date.timeIntervalSince(last)) < 60 { return }
        days[0].lastSeen = date
    }

    /// The times this reminder fires today, honouring any alignment to another
    /// reminder's timetable.
    func slots(for reminder: Reminder) -> [MinuteOfDay] {
        let window = self.window(for: reminder)
        guard let anchorID = reminder.alignsWith,
              let anchor = config.reminders.first(where: { $0.id == anchorID }),
              case .timesPerDay(let wanted) = reminder.schedule,
              wanted > 0
        else {
            return reminder.slots(global: window)
        }

        let grid = anchor.slots(global: self.window(for: anchor))
        guard grid.count >= wanted else { return reminder.slots(global: window) }
        if wanted == 1 { return [grid[0]] }

        // Spread the chosen ones evenly across the anchor's times: four of six
        // becomes the 1st, 3rd, 4th and 6th, not the first four in a row.
        let step = Double(grid.count - 1) / Double(wanted - 1)
        return (0..<wanted).map { grid[Int((Double($0) * step).rounded())] }
    }

    /// Records a stretch when the Mac was not in use, so slots that passed
    /// during it can be assumed rather than counted against you.
    func noteAway(from start: Date, to end: Date) {
        ensureToday()
        guard !days.isEmpty, end > start else { return }
        days[0].away.append(AwayPeriod(start: start, end: end))
    }



    /// When you are usually at the laptop. A quarter hour counts only if it is
    /// used on at least half the recent days, which trims the odd late night
    /// and the one early start without needing you to describe your routine.
    var learnedWork: TimeWindow? {
        let recent = days.prefix(14).filter { !$0.activeBuckets.isEmpty }
        guard recent.count >= 3 else { return nil }

        var tally: [Int: Int] = [:]
        for day in recent {
            for bucket in Set(day.activeBuckets) { tally[bucket, default: 0] += 1 }
        }
        let threshold = max(2, recent.count / 2)
        let usual = tally.filter { $0.value >= threshold }.keys.sorted()
        guard let first = usual.first, let last = usual.last, last > first else { return nil }
        return TimeWindow(start: first * 15, end: (last + 1) * 15)
    }

    var effectiveWork: TimeWindow {
        guard config.learnWorkWindow, let learned = learnedWork else { return config.work }
        return learned
    }

    /// The hours a given reminder is allowed to fire in.
    func window(for reminder: Reminder) -> TimeWindow {
        switch reminder.appliesDuring {
        case .work:   return effectiveWork
        case .custom: return reminder.window ?? effectiveWork
        }
    }

    var learnedDayCount: Int {
        days.prefix(14).filter { $0.firstSeen != nil && $0.lastSeen != nil }.count
    }

    static func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: - Writing events

    func log(_ reminder: Reminder, kind: EventKind, at date: Date = Date()) {
        ensureToday()
        guard !days.isEmpty else { return }
        let event = LogEvent(
            reminderID: reminder.id,
            at: date,
            kind: kind,
            amount: kind == .done ? reminder.amount : nil
        )
        days[0].events.append(event)
    }

    /// Removes the most recent event for a reminder today. Used by the undo
    /// button, so a mis-tap on "drank 250 ml" is not permanent.
    @discardableResult
    func undoLast(_ reminder: Reminder) -> Bool {
        guard !days.isEmpty else { return false }
        guard let idx = days[0].events.lastIndex(where: { $0.reminderID == reminder.id }) else { return false }
        days[0].events.remove(at: idx)
        return true
    }

    // MARK: - Reminder CRUD

    func reminder(id: UUID) -> Reminder? { config.reminders.first { $0.id == id } }

    func upsert(_ reminder: Reminder) {
        if let idx = config.reminders.firstIndex(where: { $0.id == reminder.id }) {
            config.reminders[idx] = reminder
        } else {
            config.reminders.append(reminder)
        }
    }

    func delete(_ reminder: Reminder) {
        config.reminders.removeAll { $0.id == reminder.id }
    }

    func resetRemindersToDefaults() {
        config.reminders = Reminder.defaultSet
    }
}
