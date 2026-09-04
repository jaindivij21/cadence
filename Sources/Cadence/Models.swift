import Foundation

// MARK: - Time of day

/// Minutes since local midnight. 8:30am == 510.
typealias MinuteOfDay = Int

extension Int {
    var asClockString: String {
        let h = self / 60, m = self % 60
        let suffix = h < 12 ? "AM" : "PM"
        var hour12 = h % 12
        if hour12 == 0 { hour12 = 12 }
        return String(format: "%d:%02d %@", hour12, m, suffix)
    }
}

struct TimeWindow: Codable, Hashable {
    var start: MinuteOfDay
    var end: MinuteOfDay

    /// Length of the window in minutes. Windows never wrap past midnight.
    var span: Int { max(0, end - start) }

    func contains(_ minute: MinuteOfDay) -> Bool {
        minute >= start && minute <= end
    }

    /// Used until there is enough history to learn from.
    static let defaultWork = TimeWindow(start: 10 * 60, end: 18 * 60)
}

// MARK: - Scheduling

enum Schedule: Codable, Hashable {
    /// Fires repeatedly, counted from the last time you acted on it.
    case everyMinutes(Int)
    /// Fires n times, spread evenly across the active window.
    case timesPerDay(Int)
    /// Fires at these exact clock times.
    case atTimes([MinuteOfDay])

    var summary: String {
        switch self {
        case .everyMinutes(let m):
            return m % 60 == 0 && m >= 60 ? "every \(m / 60)h" : "every \(m)m"
        case .timesPerDay(let n):
            return n == 1 ? "once a day" : "\(n)× a day"
        case .atTimes(let times):
            return times.map(\.asClockString).joined(separator: ", ")
        }
    }
}

enum AlertStyle: Codable, Hashable {
    /// Takes over every screen for `seconds`. Use it when you physically cannot
    /// look at the display anyway (eye breaks, drops).
    case blocking(seconds: Int)
    /// Drops a pill under the menu bar, which leaves as soon as it is answered.
    /// `sticky` keeps it there until you do.
    case toast(sticky: Bool)

    var isBlocking: Bool {
        if case .blocking = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .blocking(let s):    return "Blocks screen · \(s)s"
        case .toast(let sticky):  return sticky ? "Pill · waits for you" : "Pill · fades"
        }
    }
}

/// When a reminder is allowed to fire.
///
/// There is only one window, and it is the time you are at the laptop. A wider
/// "waking" window was tempting and dishonest: Cadence cannot reach you with
/// the lid shut, so a drop scheduled for half ten at night was never a reminder
/// — it was a thing that quietly got marked as assumed the next morning.
/// Everything is spread across the hours it can actually speak to you.
enum ScheduleWindow: String, Codable, CaseIterable, Identifiable {
    /// The hours you are at the laptop.
    case work
    /// A fixed time set on the reminder itself. Outside the window this can
    /// only ever be assumed, never prompted.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work:   return "While I'm at the laptop"
        case .custom: return "A fixed time"
        }
    }
}

// MARK: - Reminder

struct Reminder: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var detail: String
    var symbol: String
    var category: Category
    var schedule: Schedule
    var alert: AlertStyle
    var enabled: Bool = true

    /// Which window this belongs to. `custom` uses `window` below.
    var appliesDuring: ScheduleWindow = .work
    /// Only read when `appliesDuring` is `.custom`.
    var window: TimeWindow? = nil

    /// For countable reminders (water). `amount` is added to the daily total
    /// each time you complete it.
    var amount: Double? = nil
    var unit: String? = nil
    var dailyTarget: Double? = nil

    var snoozeMinutes: Int = 10

    /// Shifts this reminder's slots off the shared grid, for things that must
    /// not coincide.
    var slotOffsetMinutes: Int = 0

    /// Ride on another reminder's timetable instead of spreading independently.
    /// A drop taken four times a day picks four of the six times you are
    /// already stopping for the six-times-a-day one, so you are interrupted six
    /// times rather than twelve.
    var alignsWith: UUID? = nil

    /// Verb on the confirm button, e.g. "Logged", "Done", "Drank 250 ml".
    var actionLabel: String = "Done"

    func activeWindow(global: TimeWindow) -> TimeWindow { window ?? global }

    /// Slot times land on the quarter hour. Spreading six drops across a
    /// fifteen-hour day gives you 11:18 and 2:06, which nobody reads as a time
    /// they are meant to do something at.
    static func round(toQuarter minute: MinuteOfDay) -> MinuteOfDay {
        Int((Double(minute) / 15).rounded()) * 15
    }

    /// The clock times this reminder should fire at today, for slot-based
    /// schedules. Interval schedules return an empty array.
    func slots(global: TimeWindow) -> [MinuteOfDay] {
        let w = activeWindow(global: global)
        switch schedule {
        case .everyMinutes:
            return []
        case .atTimes(let times):
            return times.sorted()
        case .timesPerDay(let n):
            guard n > 0 else { return [] }
            let shift = slotOffsetMinutes
            if n == 1 { return [Reminder.round(toQuarter: w.start + w.span / 2 + shift)] }
            // Evenly spaced, inset from both edges so nothing lands the second
            // you wake up or the second you go to bed.
            let inset = min(30, w.span / (n * 2))
            let lo = w.start + inset
            let hi = w.end - inset
            let step = Double(hi - lo) / Double(n - 1)
            return (0..<n).map {
                let raw = min(w.end, lo + shift + Int((Double($0) * step).rounded()))
                return min(w.end, Reminder.round(toQuarter: raw))
            }
        }
    }
}

// MARK: - Log

enum EventKind: String, Codable {
    case done, skipped, missed
    /// The slot passed while the Mac was asleep, locked or shut. You were
    /// living your life; Cadence assumes you took it rather than accusing you
    /// of missing it. Counts as taken, but never adds to a measured total —
    /// you cannot assume millilitres.
    case assumed
}

struct LogEvent: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var reminderID: UUID
    var at: Date
    var kind: EventKind
    var amount: Double? = nil
}

/// A stretch when the Mac was asleep, locked or shut.
struct AwayPeriod: Codable, Hashable {
    var start: Date
    var end: Date

    func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

struct DayLog: Codable {
    var day: String                 // "yyyy-MM-dd"
    var events: [LogEvent] = []
    /// First and last moment the screen was on and unlocked that day.
    var firstSeen: Date? = nil
    var lastSeen: Date? = nil
    /// When the Mac was not in use, so a slot that passed can be told apart
    /// from one you were present for and ignored.
    var away: [AwayPeriod] = []
    /// Quarter-hour buckets (0..95) the laptop was actually in use. This is how
    /// the working window is learned: the hours you are usually at it, not the
    /// one evening you answered an email at eleven.
    var activeBuckets: [Int] = []

    /// True when the Mac was demonstrably not in use at that moment: inside a
    /// recorded gap, or before it was first opened today.
    func wasAway(at date: Date) -> Bool {
        if let first = firstSeen, date < first { return true }
        return away.contains { $0.contains(date) }
    }

    func events(for reminder: UUID) -> [LogEvent] {
        events.filter { $0.reminderID == reminder }
    }

    func handledCount(for reminder: UUID) -> Int {
        events.reduce(into: 0) { $0 += ($1.reminderID == reminder ? 1 : 0) }
    }

    func doneCount(for reminder: UUID) -> Int {
        events.reduce(into: 0) { $0 += ($1.reminderID == reminder && $1.kind == .done ? 1 : 0) }
    }

    /// What the counters show: things you did, plus things that happened while
    /// the Mac was off.
    func takenCount(for reminder: UUID) -> Int {
        events.reduce(into: 0) {
            $0 += ($1.reminderID == reminder && ($1.kind == .done || $1.kind == .assumed) ? 1 : 0)
        }
    }

    func total(for reminder: UUID) -> Double {
        events.reduce(into: 0.0) { sum, e in
            if e.reminderID == reminder, e.kind == .done { sum += e.amount ?? 0 }
        }
    }
}

// MARK: - Config

struct Config: Codable {
    var reminders: [Reminder] = Reminder.defaultSet
    /// Chord that summons the command bar. Never ⌘Space — that is Spotlight's,
    /// and Cadence has no business taking it.
    var hotKey: HotKeyChoice = .optionSpace
    var soundEnabled: Bool = true
    var menuBarCountdown: Bool = true
    var startAtLogin: Bool = false
    /// How late a missed slot can be before it is written off instead of fired.
    var slotGraceMinutes: Int = 25
    /// Never interrupt twice inside this. Answering one reminder buys you a
    /// stretch of quiet before the next can appear.
    var minimumGapMinutes: Int = 3
    /// Anything falling due within this of an interruption rides along with it
    /// instead of arriving on its own a minute later. Drink the water during
    /// the eye break.
    var groupWindowMinutes: Int = 12
    /// The only window: when you are at the laptop. Learned from the hours you
    /// actually use it, with this as the fallback and the manual override.
    var work: TimeWindow = TimeWindow(start: 10 * 60, end: 18 * 60)
    var learnWorkWindow: Bool = true
}

// MARK: - Defaults

extension Reminder {
    /// What a brand new install starts with: a handful of habits that suit
    /// anyone who sits in front of a screen all day. Everything specific —
    /// medication, therapies, routines — comes from the preset library or from
    /// a reminder you write yourself.
    static var defaultSet: [Reminder] {
        [
            PresetLibrary.eyeBreak,
            PresetLibrary.water,
            PresetLibrary.standAndMove,
            PresetLibrary.daylight,
            PresetLibrary.supplements,
            PresetLibrary.screensDown
        ]
    }
}

// MARK: - Preset library

struct PresetGroup: Identifiable {
    var id: String { name }
    let name: String
    let reminders: [Reminder]
}

/// Ready-made reminders you can drop in from Settings. Each one is a normal
/// reminder after that — rename it, re-time it, delete it.
enum PresetLibrary {

    // Screen and eyes
    static var eyeBreak: Reminder {
        Reminder(
            name: "20-20-20 Break",
            detail: "Let your eyes go long — the furthest thing in the room, or out of a window. Then blink all the way closed a few times; a half blink does nothing.",
            symbol: "eye",
            category: .eye,
            schedule: .everyMinutes(20),
            alert: .blocking(seconds: 20),
            actionLabel: "Done"
        )
    }

    static var coldCompress: Reminder {
        Reminder(
            name: "Cold Compress",
            detail: "Something cold over closed eyes for a few minutes. It calms swelling and irritation — the opposite job to a warm compress.",
            symbol: "snowflake",
            category: .eye,
            schedule: .timesPerDay(2),
            alert: .toast(sticky: true),
            actionLabel: "Done"
        )
    }

    static var warmCompress: Reminder {
        Reminder(
            name: "Warm Compress",
            detail: "Warm cloth over closed eyes for five minutes, then a gentle lid massage.",
            symbol: "flame.fill",
            category: .eye,
            schedule: .atTimes([21 * 60 + 30]),
            alert: .toast(sticky: true),
            actionLabel: "Done"
        )
    }

    static var distanceFocus: Reminder {
        Reminder(
            name: "Distance Focus",
            detail: "Pick the furthest thing you can see and hold it. Your focusing muscle has been clenched at screen distance for an hour.",
            symbol: "eye.fill",
            category: .eye,
            schedule: .everyMinutes(90),
            alert: .blocking(seconds: 30),
            actionLabel: "Done"
        )
    }

    // Medication
    static func doses(_ count: Int) -> Reminder {
        Reminder(
            name: "Drops · \(count)× daily",
            detail: "One drop in each eye. Then close them and press the inner corner, by your nose, for thirty seconds — that keeps the drop on your eye instead of draining down your throat.",
            symbol: "drop.fill",
            category: .eye,
            schedule: .timesPerDay(count),
            alert: .blocking(seconds: 25),
            actionLabel: "Taken"
        )
    }

    static var morningMeds: Reminder {
        Reminder(
            name: "Morning Medication",
            detail: "Take it with food and a full glass of water.",
            symbol: "pills.fill",
            category: .immunity,
            schedule: .atTimes([9 * 60]),
            alert: .toast(sticky: true),
            actionLabel: "Taken"
        )
    }

    static var eveningMeds: Reminder {
        Reminder(
            name: "Evening Medication",
            detail: "Take it with dinner.",
            symbol: "pills.fill",
            category: .immunity,
            schedule: .atTimes([20 * 60]),
            alert: .toast(sticky: true),
            actionLabel: "Taken"
        )
    }

    // Hydration
    static var water: Reminder {
        Reminder(
            name: "Water",
            detail: "250 ml. Sip it, do not gulp it.",
            symbol: "drop.circle.fill",
            category: .hydration,
            schedule: .timesPerDay(12),
            alert: .toast(sticky: true),
            amount: 250,
            unit: "ml",
            dailyTarget: 3000,
            actionLabel: "Drank 250 ml"
        )
    }

    static var electrolytes: Reminder {
        Reminder(
            name: "Electrolytes",
            detail: "A pinch of salt and some potassium in your water.",
            symbol: "bolt.fill",
            category: .hydration,
            schedule: .atTimes([11 * 60, 16 * 60]),
            alert: .toast(sticky: false),
            actionLabel: "Done"
        )
    }

    // Immunity and recovery
    static var coldExposure: Reminder {
        Reminder(
            name: "Cold Exposure",
            detail: "Two to three minutes cold. Slow nasal breathing, no gasping.",
            symbol: "snowflake",
            category: .immunity,
            schedule: .timesPerDay(2),
            alert: .toast(sticky: true),
            actionLabel: "Done"
        )
    }

    static var daylight: Reminder {
        Reminder(
            name: "Daylight",
            detail: "Fifteen minutes outside without sunglasses. Sets your body clock.",
            symbol: "sun.max.fill",
            category: .immunity,
            schedule: .atTimes([10 * 60 + 30]),
            alert: .toast(sticky: false),
            actionLabel: "Got it"
        )
    }

    static var supplements: Reminder {
        Reminder(
            name: "Supplements",
            detail: "With your largest meal, so the fat-soluble ones actually absorb. Keep a few hours clear of any medication — zinc, calcium, magnesium and iron all block absorption.",
            symbol: "cross.vial.fill",
            category: .immunity,
            schedule: .atTimes([13 * 60 + 30]),
            alert: .toast(sticky: true),
            actionLabel: "Taken"
        )
    }

    static var breathwork: Reminder {
        Reminder(
            name: "Breathwork",
            detail: "Four seconds in, six seconds out. Let your shoulders drop.",
            symbol: "lungs.fill",
            category: .recovery,
            schedule: .timesPerDay(2),
            alert: .blocking(seconds: 60),
            actionLabel: "Done"
        )
    }

    static var screensDown: Reminder {
        Reminder(
            name: "Screens Down",
            detail: "Last call. Dim the lights and let your eyes recover overnight.",
            symbol: "moon.stars.fill",
            category: .recovery,
            schedule: .atTimes([22 * 60 + 30]),
            alert: .blocking(seconds: 30),
            actionLabel: "Winding down"
        )
    }

    // Movement
    static var standAndMove: Reminder {
        Reminder(
            name: "Stand & Move",
            detail: "Two minutes. Walk, roll your shoulders, unclench your jaw.",
            symbol: "figure.walk",
            category: .movement,
            schedule: .everyMinutes(50),
            alert: .toast(sticky: false),
            actionLabel: "Moved"
        )
    }

    static var postureReset: Reminder {
        Reminder(
            name: "Posture Reset",
            detail: "Ears over shoulders, screen at eye level, feet flat.",
            symbol: "figure.mind.and.body",
            category: .movement,
            schedule: .everyMinutes(30),
            alert: .toast(sticky: false),
            actionLabel: "Fixed"
        )
    }

    static var mobility: Reminder {
        Reminder(
            name: "Mobility",
            detail: "Five minutes of hips, thoracic spine and wrists.",
            symbol: "figure.strengthtraining.traditional",
            category: .movement,
            schedule: .atTimes([18 * 60]),
            alert: .toast(sticky: true),
            actionLabel: "Done"
        )
    }

    // Focus
    static var shutdown: Reminder {
        Reminder(
            name: "Shutdown Ritual",
            detail: "Close the loops, write tomorrow's first task, then stop working.",
            symbol: "book.closed.fill",
            category: .recovery,
            schedule: .atTimes([19 * 60]),
            alert: .toast(sticky: true),
            actionLabel: "Done"
        )
    }

    static var groups: [PresetGroup] {
        [
            PresetGroup(name: "Screen & eyes", reminders: [eyeBreak, distanceFocus, coldCompress, warmCompress]),
            PresetGroup(name: "Medication", reminders: [doses(6), doses(4), doses(2), morningMeds, eveningMeds]),
            PresetGroup(name: "Hydration", reminders: [water, electrolytes]),
            PresetGroup(name: "Immunity & recovery", reminders: [coldExposure, daylight, supplements, breathwork, screensDown]),
            PresetGroup(name: "Movement", reminders: [standAndMove, postureReset, mobility]),
            PresetGroup(name: "Focus", reminders: [shutdown])
        ]
    }
}
