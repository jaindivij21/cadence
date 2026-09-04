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

    private static var stateURL: URL { directory.appendingPathComponent("state.json") }

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
