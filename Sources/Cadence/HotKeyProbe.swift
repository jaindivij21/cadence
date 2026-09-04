import AppKit
import Carbon.HIToolbox

/// `Cadence --hotkey-probe` reports whether each chord can actually be claimed,
/// instead of registering it and hoping. RegisterEventHotKey returns an
/// OSStatus that the app was throwing away.
@MainActor
enum HotKeyProbe {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--hotkey-probe") else { return false }

        let cases: [(String, UInt32, UInt32)] = [
            ("Space (no modifier)", UInt32(kVK_Space), 0),
            ("Option-Space",        UInt32(kVK_Space), UInt32(optionKey)),
            ("Control-Space",       UInt32(kVK_Space), UInt32(controlKey)),
            ("Shift-Space",         UInt32(kVK_Space), UInt32(shiftKey)),
            ("Shift-Command-C",     UInt32(kVK_ANSI_C), UInt32(cmdKey | shiftKey))
        ]

        for (index, item) in cases.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x50524F42), id: UInt32(index + 40))
            let status = RegisterEventHotKey(item.1, item.2, id, GetApplicationEventTarget(), 0, &ref)
            let verdict: String
            switch status {
            case noErr:   verdict = "claimed"
            case -9878:   verdict = "REFUSED — already taken by something else"
            default:      verdict = "REFUSED — OSStatus \(status)"
            }
            print(String(format: "%-22@ %@", item.0 as NSString, verdict as NSString))
            if let ref { UnregisterEventHotKey(ref) }
        }

        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        print(String(format: "seconds since last keyDown: %.1f", idle))
        return true
    }
}
