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
            // Opus 4.5 cut the rate to $5; Opus 4 / 4.1 were $15.
            if m.contains("opus-4-1") || m.contains("opus-4-20") { return 15 }
            return 5   // 4.5 / 4.6 / 4.7 / 4.8 and the bare "opus" alias
        }

        if m.contains("haiku") {
            if m.contains("haiku-3") || m.contains("3-5-haiku") { return 0.8 }
            return 1   // Haiku 4.5
        }

        // Sonnet (3.5 / 4 / 4.5 / 4.6) and any unrecognized id default here.
        return 3
    }
}
