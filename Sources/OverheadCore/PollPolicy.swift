import Foundation

/// The request quota reported by the API in its `x-ratelimit-*` headers.
public struct RateLimit: Equatable, Sendable {
    /// Requests left in the current window.
    public var remaining: Int
    /// Seconds until the window resets.
    public var resetIn: TimeInterval

    public init(remaining: Int, resetIn: TimeInterval) {
        self.remaining = remaining
        self.resetIn = resetIn
    }

    /// Reads `x-ratelimit-remaining` and `x-ratelimit-reset`. Header names
    /// are matched without regard to case.
    public init?(headers: [String: String]) {
        var remaining: Int?
        var reset: Double?
        for (name, value) in headers {
            switch name.lowercased() {
            case "x-ratelimit-remaining": remaining = Int(value.trimmingCharacters(in: .whitespaces))
            case "x-ratelimit-reset": reset = Double(value.trimmingCharacters(in: .whitespaces))
            default: break
            }
        }
        guard let remaining, let reset, reset >= 0 else { return nil }
        self.remaining = remaining
        self.resetIn = reset
    }
}

/// Decides how long to wait before the next request.
///
/// ADSB.lol allows 500 requests a day without a key, which is one every
/// 173 seconds if spread evenly. Polling every 10 seconds around the clock
/// would use that up in under 90 minutes. So: poll fast while the card is
/// open, and otherwise spread what is left of the quota over the time until
/// it resets.
public enum PollPolicy {
    /// Interval while the card is open.
    public static let activeInterval: TimeInterval = 10
    /// Interval in the background before the quota is known.
    public static let defaultIdleInterval: TimeInterval = 180
    /// Requests held back so that opening the card always works.
    public static let reserve = 40
    public static let maxBackoff: TimeInterval = 600

    public static func delay(
        cardOpen: Bool,
        rateLimit: RateLimit?,
        consecutiveFailures: Int = 0,
        retryAfter: TimeInterval? = nil
    ) -> TimeInterval {
        // The server said when to come back: do exactly that.
        if let retryAfter, retryAfter > 0 {
            return max(retryAfter, activeInterval)
        }
        // Out of quota: wait for the window to reset.
        if let rateLimit, rateLimit.remaining <= 0 {
            return max(rateLimit.resetIn, activeInterval)
        }

        var base: TimeInterval
        if cardOpen {
            base = activeInterval
        } else if let rateLimit {
            let spendable = rateLimit.remaining - reserve
            if spendable <= 0 {
                base = max(rateLimit.resetIn, activeInterval)
            } else {
                base = max(activeInterval, rateLimit.resetIn / Double(spendable))
            }
        } else {
            base = defaultIdleInterval
        }

        // Errors: double the wait each time, up to ten minutes.
        if consecutiveFailures > 0 {
            let factor = pow(2.0, Double(min(consecutiveFailures, 8)))
            base = min(max(base, activeInterval * factor), max(base, maxBackoff))
        }
        return base
    }
}
