import AppKit
import Intents
import OverheadCore

/// What the Mac is doing right now, for deciding whether a flyover would be
/// unwelcome. Everything here uses public APIs and is only read at the
/// moment a flyover is about to start: nothing polls in the background.
///
/// What macOS does and does not let an app find out:
///
/// - Focus: `INFocusStatusCenter` reports whether a Focus is on, after the
///   user grants access. It only reports "on" for a Focus in which the user
///   has left "Share Focus Status" enabled.
/// - Full screen: the system-wide presentation options say when the active
///   app has hidden the menu bar for full screen, and the window list (which
///   needs no permission for sizes and owners) confirms it.
/// - Screen sharing or recording by another app: there is no public API for
///   this, and `NSWindow.sharingType = .none` no longer hides a window from
///   capture. Only display mirroring can be detected.
@MainActor
enum SystemState {
    enum FocusAccess: Equatable {
        case allowed, denied, notAsked, unavailable

        var explanation: String {
            switch self {
            case .allowed: return "Allowed"
            case .denied: return "Denied in System Settings"
            case .notAsked: return "Not asked yet"
            case .unavailable: return "Not available"
            }
        }
    }

    static var focusAccess: FocusAccess {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: return .allowed
        case .denied: return .denied
        case .notDetermined: return .notAsked
        case .restricted: return .unavailable
        @unknown default: return .unavailable
        }
    }

    /// Shows the system's permission prompt for Focus status.
    static func requestFocusAccess() async -> FocusAccess {
        await withCheckedContinuation { continuation in
            INFocusStatusCenter.default.requestAuthorization { _ in
                continuation.resume()
            }
        }
        return focusAccess
    }

    /// True or false when access is allowed and the system reports a value;
    /// nil when it cannot be known.
    static var focusOn: Bool? {
        guard focusAccess == .allowed else { return nil }
        return INFocusStatusCenter.default.focusStatus.isFocused
    }

    static var isFullScreen: Bool {
        if NSApp.currentSystemPresentationOptions.contains(.fullScreen) { return true }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }

        let windows: [FullScreenDetector.Window] = list.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            return FullScreenDetector.Window(ownerPID: pid, layer: layer, bounds: bounds)
        }
        return FullScreenDetector.isFullScreen(
            windows: windows, frontmostPID: front.processIdentifier, screens: displayBounds
        )
    }

    private static var displayIDs: [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Display frames in the same top-left coordinate space the window list uses.
    private static var displayBounds: [CGRect] {
        displayIDs.map { CGDisplayBounds($0) }
    }

    /// True when any display is mirroring another (a projector, AirPlay mirroring).
    static var isMirrored: Bool {
        displayIDs.contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    static func conditions(now: Date = Date()) -> FlyoverConditions {
        FlyoverConditions(
            minuteOfDay: QuietHours.minuteOfDay(for: now),
            focusOn: focusOn,
            fullScreen: isFullScreen,
            screenMirrored: isMirrored
        )
    }
}
