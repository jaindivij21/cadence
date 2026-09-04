import AppKit
import ServiceManagement
import SwiftUI

/// A normal macOS settings window: a real sidebar and a grouped Form, so the
/// system draws the glass, the insets and the controls. Nothing here is
/// hand-painted.
struct SettingsView: View {
    @EnvironmentObject var store: Store

    enum Selection: Hashable {
        case general
        case reminder(UUID)
    }

    @State private var selection: Selection?

    /// `previewReminder` only exists so the preview renderer can open the
    /// editor directly. Normal callers get the General pane.
    init(previewReminder: UUID? = nil) {
        _selection = State(initialValue: previewReminder.map { Selection.reminder($0) } ?? .general)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 840, minHeight: 620)
        .containerBackground(.ultraThinMaterial, for: .window)
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
                            .foregroundStyle(reminder.enabled ? Palette.text : Palette.textFaint)
                    } icon: {
                        Image(systemName: reminder.symbol)
                            .foregroundStyle(reminder.enabled ? reminder.category.color : Palette.textFaint)
                    }
                    .tag(Selection.reminder(reminder.id))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
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
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .fixedSize()

                Spacer()

                Button("Reset") {
                    store.resetRemindersToDefaults()
                    selection = .general
                }
                .buttonStyle(.glass)
                .help("Replace every reminder with the defaults")
            }
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

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var store: Store
    @State private var loginStatus: String?

    var body: some View {
        Form {
            Section {
                DatePicker("Wake", selection: minuteBinding($store.config.waking.start), displayedComponents: .hourAndMinute)
                DatePicker("Sleep", selection: minuteBinding($store.config.waking.end), displayedComponents: .hourAndMinute)
            } header: {
                Text("Your day")
            } footer: {
                Text("Anything scheduled a set number of times a day is spread across this window.")
            }

            Section("Behaviour") {
                Toggle(isOn: $store.config.showIsland) {
                    Text("Show the floating island")
                    Text("A glass readout that sits above your desktop. Drag it anywhere.")
                }
                Toggle(isOn: $store.config.soundEnabled) {
                    Text("Play a sound with each reminder")
                    Text("A soft system tone. Nothing else.")
                }
                Toggle(isOn: $store.config.menuBarCountdown) {
                    Text("Show the countdown in the menu bar")
                    Text("Turn this off for a plain icon.")
                }
                Toggle(isOn: $store.config.startAtLogin) {
                    Text("Start Cadence at login")
                    if let loginStatus {
                        Text(loginStatus)
                    }
                }
                .onChange(of: store.config.startAtLogin) { _, newValue in
                    applyLoginItem(newValue)
                }
            }

            Section("Timing") {
                Stepper(value: $store.config.idleResetMinutes, in: 1...60) {
                    LabeledContent("Reset repeating timers after being away") {
                        Text("\(store.config.idleResetMinutes) min")
                    }
                    Text("If you have not touched the keyboard for this long, the repeating clock starts over. You already had the break.")
                }
                Stepper(value: $store.config.slotGraceMinutes, in: 5...180, step: 5) {
                    LabeledContent("Write off a missed slot after") {
                        Text("\(store.config.slotGraceMinutes) min")
                    }
                    Text("A scheduled dose this far past its time is recorded as missed instead of firing late.")
                }
            }

            Section {
                LabeledContent("Stored on this Mac") {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Store.stateURL])
                    }
                    .buttonStyle(.glass)
                }
            } footer: {
                Text("Your configuration and 30 days of history live in one file. Cadence has no network code — nothing is sent anywhere.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private func applyLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                loginStatus = "Registered as a login item."
            } else {
                try SMAppService.mainApp.unregister()
                loginStatus = "Removed from login items."
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
        case interval, perDay, fixed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .interval: return "Every N minutes"
            case .perDay:   return "N times a day"
            case .fixed:    return "At set times"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $reminder.name)
                TextField("Detail", text: $reminder.detail, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Button says", text: $reminder.actionLabel)
                Picker("Category", selection: $reminder.category) {
                    ForEach(Category.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                Toggle("Enabled", isOn: $reminder.enabled)
            } header: {
                header
            }

            Section("When") {
                Picker("Schedule", selection: scheduleKindBinding) {
                    ForEach(ScheduleKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                scheduleDetail

                Toggle(isOn: Binding(
                    get: { reminder.window != nil },
                    set: { reminder.window = $0 ? TimeWindow(start: 9 * 60, end: 18 * 60) : nil }
                )) {
                    Text("Use its own window")
                    Text("Otherwise it follows your waking hours.")
                }

                if reminder.window != nil {
                    DatePicker("From", selection: minuteBinding(Binding(
                        get: { reminder.window?.start ?? 9 * 60 },
                        set: { reminder.window?.start = $0 }
                    )), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding(Binding(
                        get: { reminder.window?.end ?? 18 * 60 },
                        set: { reminder.window?.end = $0 }
                    )), displayedComponents: .hourAndMinute)
                }
            }

            Section("How loud") {
                Picker("Style", selection: Binding(
                    get: { reminder.alert.isBlocking },
                    set: { reminder.alert = $0 ? .blocking(seconds: 20) : .toast(sticky: true) }
                )) {
                    Text("Take over the screen").tag(true)
                    Text("Ask in the island").tag(false)
                }
                .pickerStyle(.segmented)

                alertDetail
            }

            Section {
                LabeledContent("Amount each time") {
                    HStack(spacing: 8) {
                        TextField("", value: Binding(
                            get: { reminder.amount ?? 0 },
                            set: { reminder.amount = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .frame(width: 80)
                        TextField("unit", text: Binding(
                            get: { reminder.unit ?? "" },
                            set: { reminder.unit = $0.isEmpty ? nil : $0 }
                        ))
                        .frame(width: 60)
                    }
                }
                LabeledContent("Daily target") {
                    TextField("", value: Binding(
                        get: { reminder.dailyTarget ?? 0 },
                        set: { reminder.dailyTarget = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .frame(width: 80)
                }
            } header: {
                Text("Counting")
            } footer: {
                Text("Set an amount to track a running daily total, the way water does.")
            }

            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 10), spacing: 8) {
                    ForEach(Self.symbolChoices, id: \.self) { symbol in
                        Button {
                            reminder.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.ui(14))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(reminder.symbol == symbol ? reminder.category.color : Palette.textSecond)
                                .glassSquircle(
                                    radius: 10,
                                    tint: reminder.symbol == symbol ? reminder.category.color : nil,
                                    interactive: true
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Delete this reminder", systemImage: "trash", role: .destructive, action: onDelete)
                    .buttonStyle(.glass)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(reminder.name)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.symbol)
                .font(.ui(18, .semibold))
                .foregroundStyle(reminder.category.color)
                .frame(width: 44, height: 44)
                .glassCircle(tint: reminder.category.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.name)
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Palette.text)
                Text("\(reminder.schedule.summary) · \(reminder.alert.summary)")
                    .font(.ui(11.5))
                    .foregroundStyle(Palette.textSecond)
            }
            Spacer()
        }
        .textCase(nil)
        .padding(.bottom, 6)
    }

    private var scheduleKindBinding: Binding<ScheduleKind> {
        Binding(
            get: {
                switch reminder.schedule {
                case .everyMinutes: return .interval
                case .timesPerDay:  return .perDay
                case .atTimes:      return .fixed
                }
            },
            set: { kind in
                switch kind {
                case .interval: reminder.schedule = .everyMinutes(20)
                case .perDay:   reminder.schedule = .timesPerDay(3)
                case .fixed:    reminder.schedule = .atTimes([9 * 60])
                }
            }
        )
    }

    @ViewBuilder
    private var scheduleDetail: some View {
        switch reminder.schedule {
        case .everyMinutes(let minutes):
            Stepper(value: Binding(
                get: { minutes },
                set: { reminder.schedule = .everyMinutes(max(1, $0)) }
            ), in: 1...240, step: 5) {
                LabeledContent("Repeat every") { Text("\(minutes) min") }
                Text("Counted from the last time you answered it.")
            }

        case .timesPerDay(let count):
            Stepper(value: Binding(
                get: { count },
                set: { reminder.schedule = .timesPerDay(max(1, $0)) }
            ), in: 1...24) {
                LabeledContent("Times a day") { Text("\(count)×") }
                Text("Spread evenly across the active window.")
            }

        case .atTimes(let times):
            ForEach(Array(times.enumerated()), id: \.offset) { index, minute in
                HStack {
                    DatePicker("Time \(index + 1)", selection: minuteBinding(Binding(
                        get: { minute },
                        set: { newValue in
                            var updated = times
                            updated[index] = newValue
                            reminder.schedule = .atTimes(updated.sorted())
                        }
                    )), displayedComponents: .hourAndMinute)
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        var updated = times
                        updated.remove(at: index)
                        reminder.schedule = .atTimes(updated)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecond)
                }
            }
            Button("Add a time", systemImage: "plus") {
                reminder.schedule = .atTimes((times + [12 * 60]).sorted())
            }
            .buttonStyle(.glass)
        }
    }

    @ViewBuilder
    private var alertDetail: some View {
        switch reminder.alert {
        case .blocking(let seconds):
            Stepper(value: Binding(
                get: { seconds },
                set: { reminder.alert = .blocking(seconds: max(5, $0)) }
            ), in: 5...300, step: 5) {
                LabeledContent("Hold the screen for") { Text("\(seconds) sec") }
                Text("It clears itself when the countdown ends.")
            }

        case .toast(let sticky):
            Toggle(isOn: Binding(
                get: { sticky },
                set: { reminder.alert = .toast(sticky: $0) }
            )) {
                Text("Wait until I answer it")
                Text("Off means it fades after 30 seconds and is logged as missed.")
            }
            Stepper(value: $reminder.snoozeMinutes, in: 1...120, step: 5) {
                LabeledContent("Snooze button adds") { Text("\(reminder.snoozeMinutes) min") }
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
