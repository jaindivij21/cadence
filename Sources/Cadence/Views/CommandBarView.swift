import AppKit
import SwiftUI

/// The summoned bar. One field, one list, one footer. Typing filters; return
/// runs; escape closes.
struct CommandBarView: View {
    @ObservedObject var controller: CommandBarController
    @EnvironmentObject var store: Store
    @EnvironmentObject var scheduler: Scheduler

    @FocusState private var focused: Bool

    private let rowHeight: CGFloat = 52
    private let visibleRows = 6

    var body: some View {
        VStack(spacing: 0) {
            field
            if !controller.results.isEmpty {
                Divider().opacity(0.5)
                list
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 660)
        .glassPanel(radius: 26)
        .onAppear { focused = true }
        .onChange(of: controller.visible) { _, visible in
            if visible { focused = true }
        }
    }

    // MARK: - Field

    private var field: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid")
                .font(.ui(18, .regular))
                .foregroundStyle(.tertiary)

            TextField("Log something, or start a break…", text: $controller.query)
                .textFieldStyle(.plain)
                .font(.ui(22, .regular))
                .focused($focused)
                .onSubmit { controller.runSelected() }
                .onChange(of: controller.query) { _, _ in controller.selection = 0 }
                .onKeyPress(.downArrow) { controller.move(1); return .handled }
                .onKeyPress(.upArrow) { controller.move(-1); return .handled }
                .onKeyPress(.escape) { controller.hide(); return .handled }
        }
        .padding(.horizontal, 22)
        .frame(height: 68)
    }

    // MARK: - Results

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, command in
                        row(command, selected: index == controller.selection)
                            .id(command.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                controller.selection = index
                                controller.runSelected()
                            }
                            .onHover { inside in
                                if inside { controller.selection = index }
                            }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .frame(height: min(CGFloat(controller.results.count) * rowHeight + 12,
                               CGFloat(visibleRows) * rowHeight + 12))
            .onChange(of: controller.selection) { _, index in
                guard controller.results.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(controller.results[index].id, anchor: .center)
                }
            }
        }
    }

    private func row(_ command: Command, selected: Bool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: command.symbol)
                .font(.ui(13, .semibold))
                .foregroundStyle(command.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(command.tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.ui(14, .medium))
                    .lineLimit(1)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.ui(11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            if let trailing = command.trailing {
                Text(trailing)
                    .font(.ui(12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "return")
                .font(.ui(11, .semibold))
                .foregroundStyle(.tertiary)
                .opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.09) : .clear)
        )
        .padding(.horizontal, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hint("return", "Run")
            hint("escape", "Close")

            Spacer()

            if scheduler.isPaused {
                Text("Paused")
                    .font(.ui(11.5))
                    .foregroundStyle(.secondary)
            } else if let next = scheduler.upcoming.first {
                HStack(spacing: 6) {
                    Image(systemName: next.reminder.symbol)
                        .font(.ui(10, .semibold))
                        .foregroundStyle(next.reminder.category.color)
                    Text("\(next.reminder.name) in \(countdown(to: next.fireAt))")
                        .font(.ui(11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
    }

    private func hint(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.ui(9, .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.ui(11.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(scheduler.now)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600)h"
    }
}
