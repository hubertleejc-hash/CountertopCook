import Foundation

/// A countdown timer that derives its remaining time from wall-clock dates, so it keeps
/// counting no matter which view is on screen.
public struct CookTimer: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public private(set) var endDate: Date
    /// Non-nil while paused: the time that was left when the timer was paused.
    public private(set) var pausedRemaining: TimeInterval?
    /// Set once the "done" alert has fired so it only fires once.
    public var hasAlerted = false

    public init(id: UUID = UUID(), name: String, duration: TimeInterval, start: Date = Date()) {
        self.id = id
        self.name = name
        self.endDate = start.addingTimeInterval(duration)
    }

    public var isPaused: Bool { pausedRemaining != nil }

    public func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, endDate.timeIntervalSince(now))
    }

    public func isFinished(at now: Date) -> Bool {
        !isPaused && remaining(at: now) <= 0
    }

    public mutating func pause(at now: Date) {
        guard !isPaused, !isFinished(at: now) else { return }
        pausedRemaining = remaining(at: now)
    }

    public mutating func resume(at now: Date) {
        guard let pausedRemaining else { return }
        endDate = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    public mutating func addMinute(at now: Date) {
        if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + 60
        } else {
            endDate = max(endDate, now).addingTimeInterval(60)
        }
        hasAlerted = false
    }
}

public enum TimeFormat {
    /// "04:59", or "1:05:00" for an hour or more. Rounds up so a timer never shows 00:00 early.
    public static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
