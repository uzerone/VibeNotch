import Foundation

/// Per-million-token rates for OpenAI Codex CLI models. Codex's token_count
/// events report `input_tokens` (total input, incl. cached), `cached_input_tokens`,
/// `output_tokens`, and `reasoning_output_tokens`. Reasoning tokens are part of
/// the model's generated output, so they're billed at the output rate — and in
/// the observed payloads they're already folded into the totals, so we price the
/// reported `output_tokens` directly.
///
/// Rates below are OpenAI's published API prices (verified Jun 2026 from
/// developers.openai.com/api/docs/pricing). Update this one file when prices move.
struct CodexPricing {
    let input: Double        // per 1M, non-cached input
    let cachedInput: Double  // per 1M, cached input
    let output: Double       // per 1M, output (reasoning folded in)

    /// Resolves the rate for a Codex CLI model. The full Codex lineup as of
    /// Jun 2026 (developers.openai.com/codex/models):
    ///   gpt-5.5, gpt-5.5-pro, gpt-5.4, gpt-5.4-mini, gpt-5.4-nano,
    ///   gpt-5.3-codex, gpt-5.3-codex-spark, gpt-5.2 (alt).
    /// Prices marked ✓ are OpenAI's published API rates; the rest are
    /// estimated from the nearest priced sibling (models OpenAI lists in Codex
    /// but not in the public pricing table) — the token *count* is always
    /// exact, only the $ estimate inherits a sibling's rate.
    ///
    /// Order matters: version-family checks run first (newest to oldest), then
    /// the `codex` suffix. The ids are substrings of one another
    /// (`gpt-5.4-mini` contains `gpt-5.4`; `gpt-5.5-pro` contains `5.5`), and
    /// `codex` must come LAST so a future `gpt-5.5-codex`/`gpt-5.4-codex` is
    /// priced by its family rather than caught by the gpt-5.3-codex rate.
    ///
    /// `bigContext` selects the gpt-5.5 long-context tier (>272K input tokens:
    /// 2x input / 1.5x output). Other models don't list a long-context tier.
    static func forModel(_ model: String, bigContext: Bool) -> CodexPricing {
        let m = model.lowercased()

        // Version-family checks run BEFORE the codex-suffix check: a future
        // coding variant of a newer family (e.g. `gpt-5.5-codex`,
        // `gpt-5.4-codex`) contains "codex" but should be priced at its own
        // family's rate, not silently fall to the gpt-5.3-codex rate below.
        // The codex rate is specifically the gpt-5.3-codex / -spark rate.

        // gpt-5.5 family.
        if m.contains("5.5") {
            if m.contains("pro") {          // no cached-input discount ✓
                return .init(input: 30.0, cachedInput: 30.0, output: 180.0)
            }
            if bigContext {                 // >272K long-context tier ✓
                return .init(input: 10.0, cachedInput: 1.0, output: 45.0)
            }
            return .init(input: 5.0, cachedInput: 0.50, output: 30.0)   // ✓
        }
        // gpt-5.4 family — size variants before the base (substring order).
        if m.contains("5.4") {
            if m.contains("nano") { return .init(input: 0.20, cachedInput: 0.02, output: 1.25) }   // ✓
            if m.contains("mini") { return .init(input: 0.75, cachedInput: 0.075, output: 4.50) }  // ✓
            return .init(input: 2.50, cachedInput: 0.25, output: 15.0)  // ✓
        }
        // gpt-5.2 (older alternative, not in the public pricing table) —
        // estimate at the gpt-5.4 base rate, its nearest listed sibling.
        if m.contains("5.2") {
            return .init(input: 2.50, cachedInput: 0.25, output: 15.0)  // est.
        }
        // gpt-5.3-codex / -codex-spark coding models (no newer family matched
        // above). The spark research-preview variant has no public price. ✓5.3
        if m.contains("codex") {
            return .init(input: 1.75, cachedInput: 0.175, output: 14.0)
        }

        // Unknown / future model — default to gpt-5.5 (Codex's recommended
        // default). Token count is exact; the $ is a best-effort estimate.
        if bigContext {
            return .init(input: 10.0, cachedInput: 1.0, output: 45.0)
        }
        return .init(input: 5.0, cachedInput: 0.50, output: 30.0)
    }

    /// Costs one token_count delta. `input` here is the *total* input (cached
    /// included), matching Codex's `last_token_usage` shape, so we split off the
    /// cached portion and price the remainder at the standard input rate.
    static func cost(input: Int, cachedInput: Int, output: Int, model: String) -> Double {
        let bigContext = input > 272_000
        let p = forModel(model, bigContext: bigContext)
        let nonCached = max(0, input - cachedInput)
        return Double(nonCached) / 1_000_000 * p.input
             + Double(cachedInput) / 1_000_000 * p.cachedInput
             + Double(output) / 1_000_000 * p.output
    }
}
