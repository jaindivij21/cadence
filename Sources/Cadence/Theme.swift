import AppKit
import SwiftUI

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

/// The app's shape vocabulary. Capsules for readouts, circles for single
/// values, squircles for buttons — nothing else.
extension View {
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(Self.glass(tint: tint, interactive: interactive), in: .capsule)
    }

    func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(Self.glass(tint: tint, interactive: interactive), in: .circle)
    }

    func glassSquircle(radius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        glassEffect(Self.glass(tint: tint, interactive: interactive), in: .rect(cornerRadius: radius))
    }

    private static func glass(tint: Color?, interactive: Bool) -> Glass {
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
