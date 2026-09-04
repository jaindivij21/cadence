import AppKit
import SwiftUI

/// State the island window and its contents share.
@MainActor
final class IslandModel: ObservableObject {
    @Published var hovering = false
    /// A reminder being asked about inside the island, rather than in a second
    /// window that appears next to it.
    @Published var alert: Reminder?
    @Published var alertProgress: String?
}

/// The floating readout. A glass capsule for the next thing, a squircle for
/// everything else, and one ringed counter per countable habit. It expands on
/// hover and morphs in place when something is due — the same object changing
/// shape, which is what `GlassEffectContainer` and `glassEffectID` are for.
struct IslandView: View {
    @ObservedObject var model: IslandModel
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler

    var onAnswer: (Reminder, EventKind) -> Void
    var onSnooze: (Reminder) -> Void
    var onOpenSettings: () -> Void

    @Namespace private var glass

    private var expanded: Bool { model.hovering || model.alert != nil }

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 10) {
                if expanded {
                    actionsButton
                        .glassEffectID("actions", in: glass)
                }

                mainCapsule
                    .glassEffectID("main", in: glass)

                if model.alert == nil {
                    ForEach(atoms) { reminder in
                        atom(reminder)
                            .glassEffectID(reminder.id, in: glass)
                    }
                }
            }
        }
        .padding(18)
        .animation(.smooth(duration: 0.34), value: expanded)
        .animation(.smooth(duration: 0.34), value: model.alert?.id)
        .animation(.smooth(duration: 0.34), value: atoms.map(\.id))
        .opacity(expanded ? 1 : 0.9)
        .onHover { model.hovering = $0 }
    }

    // MARK: - The capsule

    @ViewBuilder
    private var mainCapsule: some View {
        if let alert = model.alert {
            alertCapsule(alert)
        } else if scheduler.isPaused {
            capsule(tint: nil) {
                glyph("pause.fill")
                Text("Paused")
                    .font(.islandValue)
                if expanded, let until = scheduler.pausedUntil {
                    Text(Fmt.clock.string(from: until))
                        .font(.islandMinor)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if let next = scheduler.upcoming.first {
            capsule(tint: nil) {
                ringIcon(next.reminder, progress: intervalProgress(next))
                Text(countdown(to: next.fireAt))
                    .font(.islandValue)
                    .contentTransition(.numericText())
                if expanded {
                    Text(next.reminder.name)
                        .font(.islandMinor)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Button(next.reminder.alert.isBlocking ? "Start" : "Log") {
                        if next.reminder.alert.isBlocking {
                            scheduler.triggerNow(next.reminder)
                        } else {
                            onAnswer(next.reminder, .done)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(next.reminder.category.color)
                    .controlSize(.small)
                }
            }
        } else {
            capsule(tint: nil) {
                glyph("checkmark")
                Text("All clear")
                    .font(.islandValue)
            }
        }
    }

    private func alertCapsule(_ reminder: Reminder) -> some View {
        capsule(tint: reminder.category.color) {
            ringIcon(reminder, progress: nil)

            VStack(alignment: .leading, spacing: 0) {
                Text(reminder.name)
                    .font(.islandValue)
                if let progress = model.alertProgress {
                    Text(progress)
                        .font(.ui(11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Button(reminder.actionLabel) { onAnswer(reminder, .done) }
                .buttonStyle(.borderedProminent)
                .tint(reminder.category.color)
                .controlSize(.small)

            Button("\(reminder.snoozeMinutes)m") { onSnooze(reminder) }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button {
                onAnswer(reminder, .skipped)
            } label: {
                Image(systemName: "xmark")
                    .font(.ui(11, .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - The other pieces

    private var actionsButton: some View {
        Menu {
            Section("Log now") {
                ForEach(store.config.reminders.filter(\.enabled)) { reminder in
                    Button(reminder.name) { onAnswer(reminder, .done) }
                }
            }
            Divider()
            if scheduler.isPaused {
                Button("Resume reminders") { scheduler.resume() }
            } else {
                Menu("Pause") {
                    Button("15 minutes") { scheduler.pause(minutes: 15) }
                    Button("1 hour") { scheduler.pause(minutes: 60) }
                    Button("3 hours") { scheduler.pause(minutes: 180) }
                }
            }
            Button("Hide the island") { store.config.showIsland = false }
            Divider()
            Button("Settings…", action: onOpenSettings)
            Button("Quit Cadence") {
                store.saveNow()
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "plus")
                .font(.ui(15, .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 44, height: 44)
        .glassSquircle(radius: 15, interactive: true)
    }

    private func atom(_ reminder: Reminder) -> some View {
        let target = slotTarget(reminder) ?? 1
        let done = store.today.doneCount(for: reminder.id)
        let left = max(0, target - done)

        return Button {
            onAnswer(reminder, .done)
        } label: {
            ZStack {
                ProgressRing(
                    progress: Double(done) / Double(max(1, target)),
                    tint: reminder.category.color,
                    lineWidth: 2,
                    track: .clear
                )
                .padding(1)
                Text("\(left)")
                    .font(.atomValue)
                    .contentTransition(.numericText())
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help("\(reminder.name): \(left) left today. Click to log one.")
    }

    private func capsule<Content: View>(
        tint: Color?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .glassCapsule(tint: tint.map { $0.opacity(0.55) })
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.ui(13, .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26)
    }

    private func ringIcon(_ reminder: Reminder, progress: Double?) -> some View {
        ZStack {
            if let progress {
                ProgressRing(progress: progress, tint: reminder.category.color, lineWidth: 2)
            }
            Image(systemName: reminder.symbol)
                .font(.ui(11, .semibold))
        }
        .frame(width: 26, height: 26)
    }

    // MARK: - Data

    /// Countable habits with something left today. Two at most — the island is
    /// a glance, not a dashboard.
    private var atoms: [Reminder] {
        store.config.reminders
            .filter { reminder in
                guard reminder.enabled, let target = slotTarget(reminder), target > 1 else { return false }
                return store.today.doneCount(for: reminder.id) < target
            }
            .prefix(2)
            .map { $0 }
    }

    private func slotTarget(_ reminder: Reminder) -> Int? {
        switch reminder.schedule {
        case .everyMinutes:       return nil
        case .timesPerDay(let n): return n
        case .atTimes(let t):     return t.count
        }
    }

    /// How far through the current interval we are, for the ring around the icon.
    private func intervalProgress(_ next: Scheduler.Upcoming) -> Double? {
        guard case .everyMinutes(let minutes) = next.reminder.schedule else { return nil }
        let total = Double(minutes) * 60
        let left = next.fireAt.timeIntervalSince(scheduler.now)
        return max(0, min(1, (total - left) / total))
    }

    private func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(scheduler.now)))
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return String(format: "%d h %02d", seconds / 3600, (seconds % 3600) / 60)
    }
}
