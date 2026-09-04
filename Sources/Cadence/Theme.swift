import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Colour

/// Cadence paints almost nothing itself. Surfaces are Liquid Glass, text is
/// semantic so macOS keeps it legible against whatever is behind it, and hue
/// only ever appears as a thin ring or a glass tint.
enum Palette {
    static let text       = Color.primary
    static let textSecond = Color.secondary
    static let textFaint  = Color.secondary.opacity(0.6)
    static let danger     = Color.red
    /// Hairline used for rings and separators drawn by hand.
    static let ring       = Color.primary.opacity(0.14)
}

enum Category: String, Codable, CaseIterable, Identifiable {
    case eye, hydration, immunity, movement, recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eye:       return "Eyes"
        case .hydration: return "Hydration"
        case .immunity:  return "Immunity"
        case .movement:  return "Movement"
        case .recovery:  return "Recovery"
        }
    }

    /// System colours, so they shift correctly with appearance and accessibility
    /// settings instead of being frozen hex values.
    var color: Color {
        switch self {
        case .eye:       return .teal
        case .hydration: return .blue
        case .immunity:  return .orange
        case .movement:  return .purple
        case .recovery:  return .pink
        }
    }
}

// MARK: - Type

extension Font {
    /// System sans. Not rounded — rounded reads as a toy.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let islandValue = Font.ui(17, .semibold)
    static let islandMinor = Font.ui(17, .regular)
    static let atomValue   = Font.ui(15, .semibold)
    static let rowTitle    = Font.ui(13, .medium)
    static let rowMinor    = Font.ui(11.5, .regular)
}

// MARK: - Glass

/// Blurs whatever is *behind the window* — the desktop, your editor, a video.
///
/// This is not the same thing as SwiftUI's `Material`. A `Material` samples
/// inside its own window, so on a borderless transparent panel it has nothing
/// to blur and renders as a flat grey sheet. Every floating Cadence surface
/// therefore sits on one of these, with Liquid Glass layered on top for the
/// refraction and the specular rim.
struct Backdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Liquid Glass is composited by the WindowServer and already samples whatever
/// is behind the window — a probe puts its in-process drawing at under 1% of
/// its own pixels. Putting a `Backdrop` underneath it, which an earlier version
/// did, gives it a sheet of frosted grey to sample instead of the desktop and
/// flattens the whole effect. Apple's guidance says the same thing: custom
/// backgrounds interfere with Liquid Glass.
///
/// So: glass on its own, and only on the floating layer. Content never wears it.
extension View {
    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        glassEffect(Self.recipe(tint, interactive), in: .capsule)
    }

    func glassPanel(radius: CGFloat = 26, tint: Color? = nil) -> some View {
        glassEffect(Self.recipe(tint, false), in: .rect(cornerRadius: radius))
    }

    private static func recipe(_ tint: Color?, _ interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// A thin arc showing how far through something you are. Used at 26pt around an
/// island icon and at 240pt around the break countdown — same control, two sizes.
struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 2
    var track: Color = Palette.ring

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Screens

extension NSScreen {
    /// The display you are actually working on.
    ///
    /// `NSScreen.main` is the screen holding the key window, which for a menu
    /// bar app with no windows of its own is whatever some other app last
    /// focused — often the wrong monitor entirely. The pointer is a far better
    /// guess at where you are looking.
    static var active: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

// MARK: - Layout plumbing

/// Reports a view's laid-out size, so a borderless window can resize itself to
/// fit content that changes shape.
private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    func measure(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: SizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizeKey.self, perform: onChange)
    }
}

// MARK: - Static rendering

/// ImageRenderer cannot capture the contents of a ScrollView, so the preview
/// renderer flips this and every scrolling region lays itself out flat.
private struct StaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var staticRender: Bool {
        get { self[StaticRenderKey.self] }
        set { self[StaticRenderKey.self] = newValue }
    }
}

/// A scroll region that becomes a plain stack while rendering previews.
struct MaybeScroll<Content: View>: View {
    @Environment(\.staticRender) private var isStatic
    @ViewBuilder var content: Content

    var body: some View {
        if isStatic {
            content
        } else {
            ScrollView { content }
                .scrollIndicators(.never)
        }
    }
}

// MARK: - Formatters

/// Allocated once. The island redraws every second.
enum Fmt {
    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    static let longDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f
    }()
    static let amount: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func amountString(_ value: Double) -> String {
        amount.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
}

// MARK: - Marquee

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One line of text that scrolls itself when it does not fit.
///
/// Truncating a sentence mid-word reads as a bug, and wrapping to two lines
/// makes the pill tall. This keeps one line and moves it, and — importantly —
/// stays perfectly still when the text already fits, so short reminders do not
/// wobble for no reason.
struct MarqueeText: View {
    let text: String
    var font: Font = .ui(12)
    /// Slow enough to read at a glance.
    var pointsPerSecond: Double = 22
    /// Blank run between the end of one pass and the start of the next.
    var gap: CGFloat = 56
    /// Time to read the opening words before anything moves.
    var startDelay: Double = 1.6

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let overflows = textWidth > proxy.size.width + 1

            HStack(spacing: gap) {
                label
                if overflows { label }
            }
            .offset(x: offset)
            .frame(width: proxy.size.width, alignment: .leading)
            .clipped()
            // A hard clip reads as a rendering fault. Fade the text out at the
            // edge it is running past instead.
            .mask(fade(leading: overflows && offset < 0, trailing: overflows))
            .onAppear { restart(overflows: overflows) }
            .onChange(of: overflows) { _, now in restart(overflows: now) }
            .onChange(of: text) { _, _ in restart(overflows: overflows) }
            .onDisappear { task?.cancel() }
        }
        .frame(height: 15)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: WidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(WidthKey.self) { textWidth = $0 }
    }

    private func fade(leading: Bool, trailing: Bool) -> some View {
        let edge = 18.0
        return GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(leading ? 0 : 1), location: 0),
                    .init(color: .black, location: leading ? edge / width : 0),
                    .init(color: .black, location: trailing ? 1 - edge / width : 1),
                    .init(color: .black.opacity(trailing ? 0 : 1), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func restart(overflows: Bool) {
        task?.cancel()
        offset = 0
        guard overflows, textWidth > 0 else { return }

        let distance = textWidth + gap
        let duration = Double(distance) / pointsPerSecond

        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(startDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -distance
            }
        }
    }
}
