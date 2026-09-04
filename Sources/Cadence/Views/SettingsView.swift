import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store

    private enum Selection: Hashable {
        case general
        case reminder(UUID)
    }

    @State private var selection: Selection

    /// `previewReminder` only exists so the preview renderer can open the
    /// editor directly. Normal callers get the General pane.
    init(previewReminder: UUID? = nil) {
        _selection = State(initialValue: previewReminder.map { Selection.reminder($0) } ?? .general)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
            Divider().overlay(Palette.hairline)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Palette.ink)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            MaybeScroll {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarRow(
                        title: "General",
                        symbol: "gearshape",
                        tint: Palette.textSecond,
                        selected: selection == .general
                    ) { selection = .general }

                    Text("REMINDERS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Palette.textFaint)
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 6)

                    ForEach(store.config.reminders) { reminder in
                        sidebarRow(
                            title: reminder.name,
                            symbol: reminder.symbol,
                            tint: reminder.category.color,
                            selected: selection == .reminder(reminder.id),
                            dimmed: !reminder.enabled
                        ) { selection = .reminder(reminder.id) }
                    }
                }
                .padding(8)
            }

            Divider().overlay(Palette.hairline)

            HStack(spacing: 8) {
                Menu {
                    Button("Blank reminder") {
                        add(Reminder(
                            name: "New reminder",
                            detail: "What should you do?",
                            symbol: "bell.fill",
                            category: .recovery,
                            schedule: .timesPerDay(2),
                            alert: .toast(sticky: true)
                        ))
                    }
                    Divider()
                    ForEach(PresetLibrary.groups) { group in
                        Menu(group.name) {
                            ForEach(group.reminders) { preset in
                                Button(preset.name) { add(preset) }
                            }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(Palette.textSecond)

                Spacer()

                Button("Reset to defaults") {
                    store.resetRemindersToDefaults()
                    selection = .general
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.textFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Palette.surface.opacity(0.5))
    }

    private func add(_ reminder: Reminder) {
        store.upsert(reminder)
        selection = .reminder(reminder.id)
    }

    private func sidebarRow(
        title: String,
        symbol: String,
        tint: Color,
        selected: Bool,
        dimmed: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textPrime)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .opacity(dimmed ? 0.4 : 1)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettings().environmentObject(store)
        case .reminder(let id):
            if let index = store.config.reminders.firstIndex(where: { $0.id == id }) {
                ReminderEditor(
                    reminder: $store.config.reminders[index],
                    onDelete: {
                        let reminder = store.config.reminders[index]
                        store.delete(reminder)
                        selection = .general
                    }
                )
                .id(id)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var store: Store
    @State private var loginStatus: String = ""

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader("Your day", "Everything scheduled a set number of times a day is spread across this window.")

                HStack(spacing: 18) {
                    TimeField(label: "Wake", minute: $store.config.waking.start)
                    TimeField(label: "Sleep", minute: $store.config.waking.end)
                    Spacer()
                }

                Divider().overlay(Palette.hairline)

                SectionHeader("Behaviour", nil)

                ToggleRow(
                    title: "Play a sound with each reminder",
                    detail: "A soft system tone. Nothing else.",
                    isOn: $store.config.soundEnabled
                )

                ToggleRow(
                    title: "Show the countdown in the menu bar",
                    detail: "Turn this off for a plain icon.",
                    isOn: $store.config.menuBarCountdown
                )

                ToggleRow(
                    title: "Start Cadence at login",
                    detail: loginStatus.isEmpty ? "Registers the app as a login item." : loginStatus,
                    isOn: $store.config.startAtLogin
                )
                .onChange(of: store.config.startAtLogin) { _, newValue in
                    applyLoginItem(newValue)
                }

                Divider().overlay(Palette.hairline)

                SectionHeader("Timing", nil)

                StepperRow(
                    title: "Reset repeating timers after being away",
                    detail: "If you have not touched the keyboard for this long, the 20-20-20 clock starts over — you already had the break.",
                    value: $store.config.idleResetMinutes,
                    range: 1...60,
                    suffix: "min"
                )

                StepperRow(
                    title: "Write off a missed slot after",
                    detail: "A scheduled dose this far past its time is recorded as missed instead of firing late.",
                    value: $store.config.slotGraceMinutes,
                    range: 5...180,
                    suffix: "min"
                )

                Divider().overlay(Palette.hairline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your data never leaves this Mac.")
                        .font(.cadenceBody)
                        .foregroundStyle(Palette.textSecond)
                    Text(Store.directory.path)
                        .font(.cadenceMono)
                        .foregroundStyle(Palette.textFaint)
                        .textSelection(.enabled)
                }
            }
            .padding(26)
            .frame(maxWidth: 660, alignment: .leading)
        }
    }

    private func applyLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                loginStatus = "Registered."
            } else {
                try SMAppService.mainApp.unregister()
                loginStatus = "Removed."
            }
        } catch {
            loginStatus = "Could not change it: \(error.localizedDescription)"
        }
    }
}

// MARK: - Reminder editor

private struct ReminderEditor: View {
    @Binding var reminder: Reminder
    var onDelete: () -> Void

    private static let symbolChoices = [
        "eye", "eye.fill", "drop.fill", "drop.circle.fill", "flame.fill",
        "snowflake", "pills.fill", "cross.vial.fill", "leaf.fill", "carrot.fill",
        "cup.and.saucer.fill", "fork.knife", "sun.max.fill", "moon.stars.fill",
        "bed.double.fill", "figure.walk", "figure.strengthtraining.traditional",
        "figure.mind.and.body", "lungs.fill", "heart.fill", "bolt.fill",
        "wind", "bell.fill", "hands.sparkles.fill", "book.closed.fill",
        "brain.head.profile", "shoeprints.fill", "timer", "alarm.fill",
        "hand.raised.fill"
    ]

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 18) {
                header

                Divider().overlay(Palette.hairline)

                SectionHeader("What it says", nil)
                LabeledField("Name") {
                    TextField("", text: $reminder.name)
                        .textFieldStyle(.plain)
                        .font(.cadenceBody)
                        .padding(8)
                        .card(radius: 8, fill: Palette.surfaceUp)
                }
                LabeledField("Detail") {
                    TextEditor(text: $reminder.detail)
                        .font(.cadenceBody)
                        .scrollContentBackground(.hidden)
                        .frame(height: 58)
                        .padding(6)
                        .card(radius: 8, fill: Palette.surfaceUp)
                }
                LabeledField("Button says") {
                    TextField("", text: $reminder.actionLabel)
                        .textFieldStyle(.plain)
                        .font(.cadenceBody)
                        .padding(8)
                        .frame(width: 200)
                        .card(radius: 8, fill: Palette.surfaceUp)
                }

                Divider().overlay(Palette.hairline)

                SectionHeader("When", nil)
                scheduleEditor

                Divider().overlay(Palette.hairline)

                SectionHeader("How loud", nil)
                alertEditor

                Divider().overlay(Palette.hairline)

                SectionHeader("Counting", "Set an amount to track a daily total, like water.")
                countingEditor

                Divider().overlay(Palette.hairline)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete this reminder", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.danger)
            }
            .padding(26)
            .frame(maxWidth: 660, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(reminder.category.color.opacity(0.15))
                Image(systemName: reminder.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(reminder.category.color)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.name)
                    .font(.cadenceTitle)
                    .foregroundStyle(Palette.textPrime)
                Text("\(reminder.schedule.summary) · \(reminder.alert.summary)")
                    .font(.cadenceLabel)
                    .foregroundStyle(Palette.textFaint)
            }

            Spacer()

            Toggle("", isOn: $reminder.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    // MARK: Schedule

    private enum ScheduleKind: String, CaseIterable { case interval, perDay, fixed }

    private var scheduleKind: ScheduleKind {
        switch reminder.schedule {
        case .everyMinutes: return .interval
        case .timesPerDay:  return .perDay
        case .atTimes:      return .fixed
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(
                get: { scheduleKind },
                set: { newKind in
                    switch newKind {
                    case .interval: reminder.schedule = .everyMinutes(20)
                    case .perDay:   reminder.schedule = .timesPerDay(3)
                    case .fixed:    reminder.schedule = .atTimes([9 * 60])
                    }
                }
            )) {
                Text("Every N minutes").tag(ScheduleKind.interval)
                Text("N times a day").tag(ScheduleKind.perDay)
                Text("At set times").tag(ScheduleKind.fixed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
            .frame(maxWidth: .infinity, alignment: .leading)

            switch reminder.schedule {
            case .everyMinutes(let minutes):
                StepperRow(
                    title: "Repeat every",
                    detail: "Counted from the last time you answered it.",
                    value: Binding(
                        get: { minutes },
                        set: { reminder.schedule = .everyMinutes(max(1, $0)) }
                    ),
                    range: 1...240,
                    suffix: "min",
                    step: 5
                )

            case .timesPerDay(let count):
                StepperRow(
                    title: "Times a day",
                    detail: "Spread evenly across your waking window.",
                    value: Binding(
                        get: { count },
                        set: { reminder.schedule = .timesPerDay(max(1, $0)) }
                    ),
                    range: 1...24,
                    suffix: "×"
                )

            case .atTimes(let times):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(times.enumerated()), id: \.offset) { index, minute in
                        HStack(spacing: 10) {
                            TimeField(label: nil, minute: Binding(
                                get: { minute },
                                set: { newValue in
                                    var updated = times
                                    updated[index] = newValue
                                    reminder.schedule = .atTimes(updated.sorted())
                                }
                            ))
                            Button {
                                var updated = times
                                updated.remove(at: index)
                                reminder.schedule = .atTimes(updated)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(Palette.textFaint)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }
                    Button {
                        reminder.schedule = .atTimes((times + [12 * 60]).sorted())
                    } label: {
                        Label("Add a time", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textSecond)
                    }
                    .buttonStyle(.plain)
                }
            }

            ToggleRow(
                title: "Use its own window",
                detail: "Otherwise it follows your waking hours.",
                isOn: Binding(
                    get: { reminder.window != nil },
                    set: { reminder.window = $0 ? TimeWindow(start: 9 * 60, end: 18 * 60) : nil }
                )
            )

            if reminder.window != nil {
                HStack(spacing: 18) {
                    TimeField(label: "From", minute: Binding(
                        get: { reminder.window?.start ?? 9 * 60 },
                        set: { reminder.window?.start = $0 }
                    ))
                    TimeField(label: "Until", minute: Binding(
                        get: { reminder.window?.end ?? 18 * 60 },
                        set: { reminder.window?.end = $0 }
                    ))
                    Spacer()
                }
            }
        }
    }

    // MARK: Alert

    private var alertEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(
                get: { reminder.alert.isBlocking },
                set: { blocking in
                    reminder.alert = blocking ? .blocking(seconds: 20) : .toast(sticky: true)
                }
            )) {
                Text("Take over the screen").tag(true)
                Text("Card in the corner").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
            .frame(maxWidth: .infinity, alignment: .leading)

            switch reminder.alert {
            case .blocking(let seconds):
                StepperRow(
                    title: "Hold the screen for",
                    detail: "It clears itself when the countdown ends.",
                    value: Binding(
                        get: { seconds },
                        set: { reminder.alert = .blocking(seconds: max(5, $0)) }
                    ),
                    range: 5...300,
                    suffix: "sec",
                    step: 5
                )
            case .toast(let sticky):
                ToggleRow(
                    title: "Wait until I answer it",
                    detail: "Off means it fades after 30 seconds and is logged as missed.",
                    isOn: Binding(
                        get: { sticky },
                        set: { reminder.alert = .toast(sticky: $0) }
                    )
                )

                StepperRow(
                    title: "Snooze button adds",
                    detail: nil,
                    value: $reminder.snoozeMinutes,
                    range: 1...120,
                    suffix: "min",
                    step: 5
                )
            }
        }
    }

    // MARK: Counting

    private var countingEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                LabeledField("Amount each time") {
                    TextField("", value: Binding(
                        get: { reminder.amount ?? 0 },
                        set: { reminder.amount = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .textFieldStyle(.plain)
                    .font(.cadenceBody)
                    .padding(8)
                    .frame(width: 90)
                    .card(radius: 8, fill: Palette.surfaceUp)
                }
                LabeledField("Unit") {
                    TextField("ml", text: Binding(
                        get: { reminder.unit ?? "" },
                        set: { reminder.unit = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.cadenceBody)
                    .padding(8)
                    .frame(width: 70)
                    .card(radius: 8, fill: Palette.surfaceUp)
                }
                LabeledField("Daily target") {
                    TextField("", value: Binding(
                        get: { reminder.dailyTarget ?? 0 },
                        set: { reminder.dailyTarget = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .textFieldStyle(.plain)
                    .font(.cadenceBody)
                    .padding(8)
                    .frame(width: 90)
                    .card(radius: 8, fill: Palette.surfaceUp)
                }
                Spacer()
            }

            LabeledField("Category") {
                Picker("", selection: $reminder.category) {
                    ForEach(Category.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            LabeledField("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10), spacing: 6) {
                    ForEach(Self.symbolChoices, id: \.self) { symbol in
                        Button {
                            reminder.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 13))
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(reminder.symbol == symbol
                                              ? reminder.category.color.opacity(0.22)
                                              : Color.white.opacity(0.05))
                                )
                                .foregroundStyle(reminder.symbol == symbol
                                                 ? reminder.category.color
                                                 : Palette.textSecond)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 356)
            }
        }
    }
}

// MARK: - Small shared controls

private struct SectionHeader: View {
    let title: String
    let detail: String?

    init(_ title: String, _ detail: String?) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Palette.textFaint)
            if let detail {
                Text(detail)
                    .font(.cadenceLabel)
                    .foregroundStyle(Palette.textSecond)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.cadenceLabel)
                .foregroundStyle(Palette.textFaint)
            content
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cadenceBody)
                    .foregroundStyle(Palette.textPrime)
                if let detail {
                    Text(detail)
                        .font(.cadenceLabel)
                        .foregroundStyle(Palette.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct StepperRow: View {
    let title: String
    let detail: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String
    var step: Int = 1

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cadenceBody)
                    .foregroundStyle(Palette.textPrime)
                if let detail {
                    Text(detail)
                        .font(.cadenceLabel)
                        .foregroundStyle(Palette.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text("\(value) \(suffix)")
                    .font(.cadenceMono)
                    .foregroundStyle(Palette.textPrime)
                    .frame(minWidth: 62, alignment: .trailing)
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// A clock-time field backed by minutes-since-midnight.
struct TimeField: View {
    let label: String?
    @Binding var minute: MinuteOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label {
                Text(label)
                    .font(.cadenceLabel)
                    .foregroundStyle(Palette.textFaint)
            }
            DatePicker("", selection: Binding(
                get: { TimeField.date(from: minute) },
                set: { minute = TimeField.minutes(from: $0) }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
        }
    }

    static func date(from minute: MinuteOfDay) -> Date {
        let start = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: minute, to: start) ?? start
    }

    static func minutes(from date: Date) -> MinuteOfDay {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
