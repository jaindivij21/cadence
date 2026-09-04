import AppKit
import SwiftUI

// MARK: - Colour helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// The whole app draws from this one palette. Deep ink background, one accent
/// per category, and a small set of neutral text tones.
enum Palette {
    static let ink        = Color(hex: 0x0B0D12)
    static let surface    = Color(hex: 0x14171F)
    static let surfaceUp  = Color(hex: 0x1C2029)
    static let hairline   = Color(hex: 0xFFFFFF, alpha: 0.08)
    static let textPrime  = Color(hex: 0xF2F4F8)
    static let textSecond = Color(hex: 0x9AA3B2)
    static let textFaint  = Color(hex: 0x606A7B)
    static let danger     = Color(hex: 0xE5484D)
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

    var color: Color {
        switch self {
        case .eye:       return Color(hex: 0x5AD7C8)   // teal
        case .hydration: return Color(hex: 0x4A9BFF)   // blue
        case .immunity:  return Color(hex: 0xFFB020)   // amber
        case .movement:  return Color(hex: 0xA78BFA)   // violet
        case .recovery:  return Color(hex: 0xF472B6)   // rose
        }
    }
}

// MARK: - Type scale

extension Font {
    static let cadenceDisplay = Font.system(size: 64, weight: .thin, design: .rounded)
    static let cadenceTitle   = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let cadenceBody    = Font.system(size: 13, weight: .regular, design: .rounded)
    static let cadenceLabel   = Font.system(size: 11, weight: .medium, design: .rounded)
    static let cadenceMono    = Font.system(size: 12, weight: .medium, design: .monospaced)
}

// MARK: - Reusable chrome

/// A soft rounded card used for every grouped block in the panel.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = Palette.surface

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(radius: CGFloat = 14, fill: Color = Palette.surface) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }
}

/// AppKit blur behind the blocking overlay, so whatever is on screen dissolves
/// instead of disappearing.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
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
