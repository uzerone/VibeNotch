import Foundation

/// Shared number/date formatting for every face of the app (island card,
/// menu-bar title, popover card). One home so "14.3k", "2h 13m left" and the
/// reset clock render identically everywhere.
enum UsageFormat {
    /// "14.3k", "1.25M", "532".
    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Whole-number percent from a 0…1 fraction — matches Anthropic's display.
    static func percent(_ u: Double) -> String {
        let v = max(0, min(100, u * 100))
        return "\(Int(v.rounded()))%"
    }

    /// "8:23 AM" (or "20:23" in 24-hour locales).
    static func clock(_ d: Date) -> String {
        clockFormatter.string(from: d)
    }

    /// "Sun 5:00 PM" — weekday + short time, for weekly resets. Built from a
    /// localized template (`j` picks the locale's 12/24-hour cycle) instead of
    /// a hard-coded `h:mm a`, so 24-hour users don't get AM/PM.
    static func weekday(_ d: Date) -> String {
        weekdayFormatter.string(from: d)
    }

    /// "5s ago", "3m ago", "2h ago".
    static func relative(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }

    /// Human countdown to a reset instant — "2h 13m left", "45m left", or
    /// "resetting…" once the moment has passed.
    static func countdown(to end: Date, now: Date = Date()) -> String {
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return "resetting…" }
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m left" }
        return "\(m)m left"
    }

    /// Elapsed time since `start` — "1h 23m" / "45m".
    static func elapsed(since start: Date, now: Date = Date()) -> String {
        let e = max(0, now.timeIntervalSince(start))
        let h = Int(e) / 3600
        let m = (Int(e) % 3600) / 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%dm", m)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Ejmm")
        return f
    }()
}

extension UsageSnapshot {
    /// The authoritative reset instant for the current session/block — the
    /// Anthropic-reported time when available, else the local block end, or
    /// `nil` when neither exists.
    var sessionResetDate: Date? {
        planUsage?.fiveHour?.resetsAt ?? blockStart?.addingTimeInterval(5 * 3600)
    }

    /// Fraction of the local 5h block elapsed — the progress-bar fallback
    /// when no plan-% gauge is available.
    func blockProgress(asOf now: Date) -> Double {
        guard let start = blockStart else { return 0 }
        return max(0, min(1, now.timeIntervalSince(start) / (5 * 3600)))
    }
}
