import Foundation

/// Swift's synthesized `Codable` ignores default values: a property with a
/// default still fails to decode if its key is missing. So every time this app
/// gained a setting, every existing state.json became undecodable — and because
/// loading swallowed the error and fell back to defaults, the next debounced
/// save wrote those defaults straight over the file. Adding a field silently
/// destroyed your configuration.
///
/// Everything persisted therefore decodes by hand, through this, and treats a
/// missing or unreadable value as "use the default" rather than as a reason to
/// throw the file away.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) as? T ?? fallback
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

extension Config {
    enum CodingKeys: String, CodingKey {
        case reminders, work, learnWorkWindow, hotKey, pillHotKey, soundEnabled
        case menuBarCountdown, startAtLogin, slotGraceMinutes
        case minimumGapMinutes, groupWindowMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = Config()
        // One unreadable reminder must not cost you the other nine.
        reminders = (try? c.decode([FailSoft<Reminder>].self, forKey: .reminders))?
            .compactMap(\.value) ?? fresh.reminders
        work = c.value(.work, or: fresh.work)
        learnWorkWindow = c.value(.learnWorkWindow, or: fresh.learnWorkWindow)
        hotKey = c.value(.hotKey, or: fresh.hotKey)
        pillHotKey = c.value(.pillHotKey, or: fresh.pillHotKey)
        soundEnabled = c.value(.soundEnabled, or: fresh.soundEnabled)
        menuBarCountdown = c.value(.menuBarCountdown, or: fresh.menuBarCountdown)
        startAtLogin = c.value(.startAtLogin, or: fresh.startAtLogin)
        slotGraceMinutes = c.value(.slotGraceMinutes, or: fresh.slotGraceMinutes)
        minimumGapMinutes = c.value(.minimumGapMinutes, or: fresh.minimumGapMinutes)
        groupWindowMinutes = c.value(.groupWindowMinutes, or: fresh.groupWindowMinutes)
    }
}

extension Reminder {
    enum CodingKeys: String, CodingKey {
        case id, name, detail, symbol, category, schedule, alert, enabled
        case appliesDuring, window, amount, unit, dailyTarget, snoozeMinutes
        case actionLabel, slotOffsetMinutes, alignsWith
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Name and schedule are the parts a reminder cannot be guessed without.
        name = try c.decode(String.self, forKey: .name)
        schedule = try c.decode(Schedule.self, forKey: .schedule)

        id = c.value(.id, or: UUID())
        detail = c.value(.detail, or: "")
        symbol = c.value(.symbol, or: "bell.fill")
        category = c.value(.category, or: .recovery)
        alert = c.value(.alert, or: .toast(sticky: true))
        enabled = c.value(.enabled, or: true)
        appliesDuring = c.value(.appliesDuring, or: .work)
        window = c.optional(.window)
        amount = c.optional(.amount)
        unit = c.optional(.unit)
        dailyTarget = c.optional(.dailyTarget)
        snoozeMinutes = c.value(.snoozeMinutes, or: 10)
        actionLabel = c.value(.actionLabel, or: "Done")
        slotOffsetMinutes = c.value(.slotOffsetMinutes, or: 0)
        alignsWith = c.optional(.alignsWith)
    }
}

extension DayLog {
    enum CodingKeys: String, CodingKey {
        case day, events, firstSeen, lastSeen, away, activeBuckets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        events = (try? c.decode([FailSoft<LogEvent>].self, forKey: .events))?
            .compactMap(\.value) ?? []
        firstSeen = c.optional(.firstSeen)
        lastSeen = c.optional(.lastSeen)
        away = c.value(.away, or: [])
        activeBuckets = c.value(.activeBuckets, or: [])
    }
}

/// A value that decodes to nil instead of failing, so one rotten element in an
/// array does not take the array with it.
struct FailSoft<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// `ScheduleWindow` has lost a case before (`day`). An unknown one now means
/// "the ordinary window", not "discard this reminder".
extension ScheduleWindow {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScheduleWindow(rawValue: raw) ?? .work
    }
}

extension HotKeyChoice {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HotKeyChoice(rawValue: raw) ?? .optionSpace
    }
}
