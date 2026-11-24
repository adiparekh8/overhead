import CoreGraphics
import Foundation

/// A daily time range such as 22:00 to 07:00, in minutes after midnight.
public struct QuietHours: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = ((start % 1440) + 1440) % 1440
        self.end = ((end % 1440) + 1440) % 1440
    }

    /// True when `minuteOfDay` is inside the range. The range may run past
    /// midnight. A range whose start equals its end is empty.
    public func contains(minuteOfDay: Int) -> Bool {
        let minute = ((minuteOfDay % 1440) + 1440) % 1440
        if start == end { return false }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    public static func minuteOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Why a flyover is not being shown.
public enum FlyoverBlock: String, Equatable, Sendable {
    case paused
    case quietHours
    case focus
    case fullScreen
    case screenMirrored

    public var explanation: String {
        switch self {
        case .paused: return "Flyovers are paused"
        case .quietHours: return "Quiet hours"
        case .focus: return "A Focus is on"
        case .fullScreen: return "An app is in full screen"
        case .screenMirrored: return "The display is being mirrored"
        }
    }
}

/// What is known about the Mac right now. `nil` means "could not tell".
public struct FlyoverConditions: Equatable, Sendable {
    public var minuteOfDay: Int
    public var focusOn: Bool?
    public var fullScreen: Bool
    public var screenMirrored: Bool

    public init(minuteOfDay: Int, focusOn: Bool?, fullScreen: Bool, screenMirrored: Bool) {
        self.minuteOfDay = minuteOfDay; self.focusOn = focusOn
        self.fullScreen = fullScreen; self.screenMirrored = screenMirrored
    }
}

/// The user's choices about when flyovers stay away.
public struct FlyoverRules: Equatable, Sendable {
    public var paused = false
    public var quietHoursEnabled = false
    public var quietHours = QuietHours(start: 22 * 60, end: 7 * 60)
    public var respectFocus = true
    public var respectFullScreen = true
    public var respectMirroring = true

    public init() {}

    /// The first reason to hold a flyover back, or nil to let it fly.
    /// An unknown Focus state (`nil`) does not block.
    public func block(_ now: FlyoverConditions) -> FlyoverBlock? {
        if paused { return .paused }
        if quietHoursEnabled, quietHours.contains(minuteOfDay: now.minuteOfDay) { return .quietHours }
        if respectFocus, now.focusOn == true { return .focus }
        if respectFullScreen, now.fullScreen { return .fullScreen }
        if respectMirroring, now.screenMirrored { return .screenMirrored }
        return nil
    }
}

/// Works out whether the frontmost app has a full-screen window, from the
/// window list.
public enum FullScreenDetector {
    public struct Window: Equatable, Sendable {
        public var ownerPID: Int32
        /// 0 for ordinary app windows.
        public var layer: Int
        public var bounds: CGRect

        public init(ownerPID: Int32, layer: Int, bounds: CGRect) {
            self.ownerPID = ownerPID; self.layer = layer; self.bounds = bounds
        }
    }

    /// True when the frontmost app owns an ordinary window that covers a
    /// whole screen. `windows` and `screens` use the same coordinate space.
    public static func isFullScreen(windows: [Window], frontmostPID: Int32, screens: [CGRect]) -> Bool {
        func covers(_ bounds: CGRect, _ screen: CGRect) -> Bool {
            let sameOrigin = abs(bounds.minX - screen.minX) < 1 && abs(bounds.minY - screen.minY) < 1
            let sameSize = abs(bounds.width - screen.width) < 1 && abs(bounds.height - screen.height) < 1
            return sameOrigin && sameSize
        }
        for window in windows where window.ownerPID == frontmostPID && window.layer == 0 {
            for screen in screens where covers(window.bounds, screen) {
                return true
            }
        }
        return false
    }
}
