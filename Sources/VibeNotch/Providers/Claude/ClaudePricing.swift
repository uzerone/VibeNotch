import Foundation

/// Per-million-token rates for Claude models.
///
/// Every Claude model prices as fixed multiples of its base input rate
/// (verified against the Claude Code CLI's own pricing table across Fable 5,
/// Opus 4.x, Sonnet, and Haiku):
///   • output         = 5×   input
///   • 5-minute cache = 1.25× input
///   • 1-hour cache   = 2×    input
///   • cache read     = 0.1×  input
/// So a model's whole rate card collapses to a single number — the input rate.
struct ModelPricing {
    let input: Double
    let output: Double
    let cacheWrite5m: Double
    let cacheWrite1h: Double
    let cacheRead: Double

    init(inputPerMTok: Double) {
        self.input = inputPerMTok
        self.output = inputPerMTok * 5
        self.cacheWrite5m = inputPerMTok * 1.25
        self.cacheWrite1h = inputPerMTok * 2
        self.cacheRead = inputPerMTok * 0.1
    }

    static func forModel(_ model: String) -> ModelPricing {
        ModelPricing(inputPerMTok: inputRate(for: model.lowercased()))
    }

    /// Base input $/MTok per model family. Current models are flat-rate — the
    /// >200k "long context" premium that older Sonnet/Opus had is gone for
    /// Fable 5, Opus 4.5+, Sonnet 4.6, and Haiku 4.5, so there's no context
    /// tier to branch on here.
    private static func inputRate(for m: String) -> Double {
        // Fable 5 / Mythos 5 — the flagship tier.
        if m.contains("fable") || m.contains("mythos") { return 10 }

        if m.contains("opus") {
            // Opus 4.5 cut the rate to $5; Opus 4.0–4.4 were $15. Match on the
            // minor version at a digit boundary rather than a bare substring,
            // so a future id like "opus-4-10" isn't caught by an "opus-4-1"
            // prefix and mispriced at the old 3× rate (the prior overcharge
            // bug's exact shape). Unparsed/bare "opus" → current $5 tier.
            if let minor = opusMinorVersion(m), minor < 5 { return 15 }
            return 5
        }

        if m.contains("haiku") {
            if m.contains("haiku-3") || m.contains("3-5-haiku") { return 0.8 }
            return 1   // Haiku 4.5
        }

        // Sonnet (3.5 / 4 / 4.5 / 4.6) and any unrecognized id default here.
        return 3
    }

    /// Extracts the Opus minor version from ids shaped `opus-<major>-<minor>`
    /// (e.g. "claude-opus-4-8" → 8, "claude-opus-4-1-20250805" → 1). The bare
    /// "claude-opus-4-20250514" (Opus 4.0, where the trailing group is a date,
    /// not a minor) resolves to minor 0 via the major-only fallback. Returns
    /// nil when no `opus-<digit>` group is present (bare "opus" alias).
    private static func opusMinorVersion(_ m: String) -> Int? {
        guard let r = m.range(of: "opus-") else { return nil }
        let rest = m[r.upperBound...]
        // Split the version tail into numeric groups: "4-8" → [4, 8];
        // "4-20250514" → [4, 20250514]; "4-1-20250805" → [4, 1, 20250805].
        let groups = rest.split(separator: "-").prefix { $0.allSatisfy(\.isNumber) }
            .compactMap { Int($0) }
        guard let major = groups.first, major == 4 else {
            // Opus 5+ (or any non-4 major) is on the current rate tier.
            return groups.first
        }
        // A second group is the minor only when it's a small number; a long
        // run of digits is a date stamp (Opus 4.0), so treat minor as 0.
        if groups.count >= 2, groups[1] < 100 { return groups[1] }
        return 0
    }
}
