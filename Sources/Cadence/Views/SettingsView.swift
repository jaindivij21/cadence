import AppKit
import ServiceManagement
import SwiftUI

/// Settings is laid out by hand rather than by `Form`. A grouped Form gives you
/// grey capsules stretched edge to edge with the control pinned to the far
/// margin — correct, characterless, and unreadable at this width. The controls
/// themselves stay standard, so they still pick up Liquid Glass; only the
/// column, the rhythm and the hierarchy are ours.
struct SettingsView: View {
    @EnvironmentObject var store: Store

    enum Selection: Hashable {
        case general
        case reminder(UUID)
    }

    @State private var selection: Selection?

    init(previewReminder: UUID? = nil) {
        _selection = State(initialValue: previewReminder.map { Selection.reminder($0) } ?? .general)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 232, ideal: 248, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 860, minHeight: 640)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Label("General", systemImage: "gearshape")
                .tag(Selection.general)

            Section("Reminders") {
                ForEach(store.config.reminders) { reminder in
                    Label {
                        Text(reminder.name)
                    } icon: {
                        Image(systemName: reminder.symbol)
                            .foregroundStyle(reminder.category.color)
                    }
                    .opacity(reminder.enabled ? 1 : 0.45)
                    .tag(Selection.reminder(reminder.id))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
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
                    Label("Add reminder", systemImage: "plus")
                }
                .menuStyle(.button)
                .fixedSize()

                Spacer()

                Menu {
                    Button("Reset every reminder to the defaults", role: .destructive) {
                        store.resetRemindersToDefaults()
                        selection = .general
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .controlSize(.small)
            .padding(12)
        }
    }

    private func add(_ reminder: Reminder) {
        store.upsert(reminder)
        selection = .reminder(reminder.id)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
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
                ContentUnavailableView("Nothing selected", systemImage: "bell.slash")
            }
        default:
            GeneralSettings().environmentObject(store)
        }
    }
}

// MARK: - The column

/// Every pane is the same shape: a fixed-width column, left aligned, with a
/// large title and generous vertical rhythm. Nothing stretches to the window
/// edge, so a wide window means more margin, not longer rows.
private struct Pane<Content: View>: View {
    let title: String
    let subtitle: String?
    var accessory: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 34) {
                HStack(alignment: .center, spacing: 14) {
                    if let accessory { accessory }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.ui(26, .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.ui(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                content
            }
            .frame(width: 520, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled run of rows. The title is a plain label, not a boxed header — the
/// spacing does the grouping.
private struct Group_<Content: View>: View {
    let title: String
    var footnote: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.ui(10.5, .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                content
            }

            if let footnote {
                Text(footnote)
                    .font(.ui(11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }
}

/// Label left, control right, inside the column. The control keeps its natural
/// size instead of being flung at the window margin.
private struct Row<Control: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.ui(13))
                if let detail {
                    Text(detail)
                        .font(.ui(11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
                .fixedSize()
        }
    }
}

/// A real switch. `Toggle` on its own draws a checkbox outside a Form.
private struct SwitchToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var store: Store
    @State private var loginStatus: String?

    var body: some View {
        Pane(title: "Cadence", subtitle: "How and when it interrupts you") {
            Group_(
                title: "Your hours",
                footnote: "Everything is spread across the hours you are at the laptop, because those are the only hours Cadence can actually reach you. A reminder set for half ten at night with the lid shut is not a reminder."
            ) {
                Row(
                    label: "Work them out from my Mac",
                    detail: learnedSummary
                ) {
                    SwitchToggle(isOn: $store.config.learnWorkWindow)
                }

                if !store.config.learnWorkWindow || store.learnedWork == nil {
                    Row(label: "From") {
                        DatePicker("", selection: minuteBinding($store.config.work.start), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 118)
                    }
                    Row(label: "Until") {
                        DatePicker("", selection: minuteBinding($store.config.work.end), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 118)
                    }
                }
            }

            Group_(
                title: "Command bar",
                footnote: "Press it anywhere to log something, start a break or pause. ⌘Space is not on the list — that belongs to Spotlight."
            ) {
                Row(label: "Summon with") {
                    Picker("", selection: $store.config.hotKey) {
                        ForEach(HotKeyChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Row(
                    label: "Answer a pill with",
                    detail: "A chord, not a bare key. The pill holds no focus, so a plain spacebar would have to be taken from whatever you are typing into."
                ) {
                    Picker("", selection: $store.config.pillHotKey) {
                        ForEach(HotKeyChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            Group_(title: "Behaviour") {
                Row(label: "Sound with each reminder", detail: "A soft system tone. Nothing else.") {
                    SwitchToggle(isOn: $store.config.soundEnabled)
                }
                Row(label: "Countdown in the menu bar", detail: "Off gives you a plain icon.") {
                    SwitchToggle(isOn: $store.config.menuBarCountdown)
                }
                Row(label: "Start at login", detail: loginStatus) {
                    SwitchToggle(isOn: $store.config.startAtLogin)
                        .onChange(of: store.config.startAtLogin) { _, value in applyLoginItem(value) }
                }
            }

            Group_(
                title: "Timing",
                footnote: "Cadence watches the screen, not the keyboard. Reading without typing still counts as looking at it — that is exactly when your eyes need the break. The clocks only hold when the display sleeps or the Mac locks."
            ) {
                Row(
                    label: "Write off a missed slot after",
                    detail: "Later than this it is recorded as missed, not fired late."
                ) {
                    Stepper("\(store.config.slotGraceMinutes) min", value: $store.config.slotGraceMinutes, in: 5...180, step: 5)
                        .monospacedDigit()
                }
            }

            Group_(
                title: "Your data",
                footnote: "Configuration and 30 days of history, in one file. Cadence has no network code — nothing is sent anywhere."
            ) {
                Row(label: "Stored on this Mac") {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Store.stateURL])
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    /// What the learned window currently says, in plain words.
    private var learnedSummary: String {
        guard let learned = store.learnedWork else {
            return "Watching. It needs three days before it will guess; until then it uses the times below."
        }
        let days = store.learnedDayCount
        return "\(learned.start.asClockString) to \(learned.end.asClockString), from \(days) day\(days == 1 ? "" : "s") of use."
    }


    private func applyLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                loginStatus = "Registered as a login item."
            } else {
                try SMAppService.mainApp.unregister()
                loginStatus = nil
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

    private enum ScheduleKind: String, CaseIterable, Identifiable {
        case interval, perDay, fixed, endOfDay
        var id: String { rawValue }
        var title: String {
            switch self {
            case .interval: return "Interval"
            case .perDay:   return "Per day"
            case .fixed:    return "Set times"
            case .endOfDay: return "End of day"
            }
        }
    }

    var body: some View {
        Pane(
            title: reminder.name,
            subtitle: "\(reminder.schedule.summary) · \(reminder.alert.summary)",
            accessory: AnyView(
                Image(systemName: reminder.symbol)
                    .font(.ui(20, .semibold))
                    .foregroundStyle(reminder.category.color)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(reminder.category.color.opacity(0.15))
                    )
            )
        ) {
            Group_(title: "What it says") {
                TextField("Name", text: $reminder.name)
                TextField("Detail", text: $reminder.detail, axis: .vertical)
                    .lineLimit(2...4)
                Row(label: "Button says") {
                    TextField("", text: $reminder.actionLabel).frame(width: 180)
                }
                Row(label: "Category") {
                    Picker("", selection: $reminder.category) {
                        ForEach(Category.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Row(label: "Enabled") {
                    SwitchToggle(isOn: $reminder.enabled)
                }
            }

            Group_(title: "When") {
                Picker("", selection: scheduleKindBinding) {
                    ForEach(ScheduleKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                scheduleDetail

                Row(label: "Applies during", detail: appliesDetail) {
                    Picker("", selection: $reminder.appliesDuring) {
                        ForEach(ScheduleWindow.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                if reminder.appliesDuring == .custom {
                    Row(label: "From") {
                        DatePicker("", selection: minuteBinding(Binding(
                            get: { reminder.window?.start ?? 9 * 60 },
                            set: { reminder.window?.start = $0 }
                        )), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 118)
                    }
                    Row(label: "Until") {
                        DatePicker("", selection: minuteBinding(Binding(
                            get: { reminder.window?.end ?? 18 * 60 },
                            set: { reminder.window?.end = $0 }
                        )), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 118)
                    }
                }
            }

            Group_(title: "How loud") {
                Picker("", selection: Binding(
                    get: { reminder.alert.isBlocking },
                    set: { reminder.alert = $0 ? .blocking(seconds: 20) : .toast(sticky: true) }
                )) {
                    Text("Take over the screen").tag(true)
                    Text("Drop a pill in").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                alertDetail
            }

            Group_(
                title: "Counting",
                footnote: "Give it an amount to track a running daily total, the way water does."
            ) {
                Row(label: "Each time") {
                    HStack(spacing: 8) {
                        TextField("", value: Binding(
                            get: { reminder.amount ?? 0 },
                            set: { reminder.amount = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .frame(width: 74)
                        TextField("unit", text: Binding(
                            get: { reminder.unit ?? "" },
                            set: { reminder.unit = $0.isEmpty ? nil : $0 }
                        ))
                        .frame(width: 56)
                    }
                }
                Row(label: "Daily target") {
                    TextField("", value: Binding(
                        get: { reminder.dailyTarget ?? 0 },
                        set: { reminder.dailyTarget = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .frame(width: 74)
                }
            }

            Group_(title: "Icon") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 10),
                    spacing: 8
                ) {
                    ForEach(Self.symbolChoices, id: \.self) { symbol in
                        let picked = reminder.symbol == symbol
                        Button {
                            reminder.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.ui(14))
                                .foregroundStyle(picked ? reminder.category.color : .secondary)
                                .frame(width: 38, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(picked ? reminder.category.color.opacity(0.18) : Color.primary.opacity(0.05))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("Delete this reminder", systemImage: "trash", role: .destructive, action: onDelete)
                .controlSize(.small)
        }
    }

    private var appliesDetail: String {
        switch reminder.appliesDuring {
        case .work:   return "Spread across the hours you are at the laptop."
        case .custom: return "A fixed clock time. Outside your hours Cadence cannot prompt you — it will only be assumed."
        }
    }

    private var scheduleKindBinding: Binding<ScheduleKind> {
        Binding(
            get: {
                switch reminder.schedule {
                case .everyMinutes: return .interval
                case .timesPerDay:  return .perDay
                case .atTimes:      return .fixed
                case .beforeEnd:    return .endOfDay
                }
            },
            set: { kind in
                switch kind {
                case .interval: reminder.schedule = .everyMinutes(20)
                case .perDay:   reminder.schedule = .timesPerDay(3)
                case .fixed:    reminder.schedule = .atTimes([9 * 60])
                case .endOfDay: reminder.schedule = .beforeEnd(minutes: 15)
                }
            }
        )
    }

    @ViewBuilder
    private var scheduleDetail: some View {
        switch reminder.schedule {
        case .everyMinutes(let minutes):
            Row(label: "Repeat every", detail: "Counted from the last time you answered it.") {
                Stepper("\(minutes) min", value: Binding(
                    get: { minutes },
                    set: { reminder.schedule = .everyMinutes(max(1, $0)) }
                ), in: 1...240, step: 5)
                .monospacedDigit()
            }

        case .timesPerDay(let count):
            Row(label: "Times a day", detail: "Spread evenly across the active window.") {
                Stepper("\(count)×", value: Binding(
                    get: { count },
                    set: { reminder.schedule = .timesPerDay(max(1, $0)) }
                ), in: 1...24)
                .monospacedDigit()
            }

        case .beforeEnd(let minutes):
            Row(label: "Before I finish", detail: "Moves with your hours as they are learned, so it is always on your way out.") {
                Stepper("\(minutes) min", value: Binding(
                    get: { minutes },
                    set: { reminder.schedule = .beforeEnd(minutes: max(0, $0)) }
                ), in: 0...180, step: 15)
                .monospacedDigit()
            }

        case .atTimes(let times):
            ForEach(Array(times.enumerated()), id: \.offset) { index, minute in
                Row(label: "Time \(index + 1)") {
                    HStack(spacing: 8) {
                        DatePicker("", selection: minuteBinding(Binding(
                            get: { minute },
                            set: { newValue in
                                var updated = times
                                updated[index] = newValue
                                reminder.schedule = .atTimes(updated.sorted())
                            }
                        )), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 118)

                        Button {
                            var updated = times
                            updated.remove(at: index)
                            reminder.schedule = .atTimes(updated)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button("Add a time", systemImage: "plus") {
                reminder.schedule = .atTimes((times + [12 * 60]).sorted())
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var alertDetail: some View {
        switch reminder.alert {
        case .blocking(let seconds):
            Row(label: "Hold the screen for", detail: "It clears itself when the countdown ends.") {
                Stepper("\(seconds) sec", value: Binding(
                    get: { seconds },
                    set: { reminder.alert = .blocking(seconds: max(5, $0)) }
                ), in: 5...300, step: 5)
                .monospacedDigit()
            }

        case .toast(let sticky):
            Row(label: "Wait until I answer", detail: "Off means it fades after 30 seconds and is logged as missed.") {
                SwitchToggle(isOn: Binding(
                    get: { sticky },
                    set: { reminder.alert = .toast(sticky: $0) }
                ))
            }
            Row(label: "Snooze adds") {
                Stepper("\(reminder.snoozeMinutes) min", value: $reminder.snoozeMinutes, in: 1...120, step: 5)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Minutes ↔ Date

/// `DatePicker` speaks `Date`; reminders store minutes since midnight, because
/// that is what survives a day boundary.
func minuteBinding(_ minute: Binding<MinuteOfDay>) -> Binding<Date> {
    Binding(
        get: {
            let start = Calendar.current.startOfDay(for: Date())
            return Calendar.current.date(byAdding: .minute, value: minute.wrappedValue, to: start) ?? start
        },
        set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minute.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    )
}
