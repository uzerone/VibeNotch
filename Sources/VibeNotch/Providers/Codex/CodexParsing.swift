import Foundation

/// One Codex `token_count` event, priced. `deltaTokens`/`cost` come from
/// `last_token_usage` (the per-turn delta — summing deltas reconstructs the
/// session's cumulative `total_token_usage`, so no cross-file dedup is needed).
struct CodexEntry {
    let ts: Date
    let deltaTokens: Int
    let cost: Double
    /// Model attributed from the nearest preceding `turn_context` line.
    let model: String
}

/// Rate-limit window as Codex emits it inside each `token_count` event. Maps
/// onto `PlanBudget` — `used_percent` is 0-100, `resets_at` is epoch seconds.
struct CodexRateWindow {
    let usedPercent: Double
    let resetsAt: Date?
}

/// Parsing helpers for Codex `rollout-*.jsonl` session files. All functions are
/// pure (no I/O) so they can be unit-checked against captured lines.
enum CodexParsing {
    static let defaultModel = "gpt-5.5"

    /// Extracts the model from a `turn_context` line's payload, if present.
    static func model(fromTurnContext obj: [String: Any]) -> String? {
        guard (obj["type"] as? String) == "turn_context",
              let payload = obj["payload"] as? [String: Any] else { return nil }
        return payload["model"] as? String
    }

    /// Extracts reasoning effort (`"low"`/`"medium"`/`"high"`) from a
    /// `turn_context` line's payload, if present.
    static func effort(fromTurnContext obj: [String: Any]) -> String? {
        guard (obj["type"] as? String) == "turn_context",
              let payload = obj["payload"] as? [String: Any] else { return nil }
        return payload["effort"] as? String
    }

    /// True if the line is an `event_msg` whose `payload.type` matches `kind`
    /// (e.g. `"token_count"`, `"task_started"`, `"task_complete"`).
    static func eventType(_ obj: [String: Any]) -> String? {
        guard (obj["type"] as? String) == "event_msg",
              let payload = obj["payload"] as? [String: Any] else { return nil }
        return payload["type"] as? String
    }

    /// Parses a `token_count` line into (delta tokens, delta cost) using the
    /// given `model`, plus the fresh rate-limit windows. Returns nil for
    /// non-token_count lines.
    static func tokenCount(_ obj: [String: Any], model: String)
        -> (delta: Int, cost: Double, primary: CodexRateWindow?, secondary: CodexRateWindow?)? {
        guard eventType(obj) == "token_count",
              let payload = obj["payload"] as? [String: Any],
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any] else { return nil }

        let input = (last["input_tokens"] as? Int) ?? 0
        let cached = (last["cached_input_tokens"] as? Int) ?? 0
        let output = (last["output_tokens"] as? Int) ?? 0
        let reasoning = (last["reasoning_output_tokens"] as? Int) ?? 0
        let total = (last["total_tokens"] as? Int) ?? (input + output)

        // reasoning_output_tokens is part of generated output; in observed
        // payloads it's already inside output_tokens (total == input + output).
        // Guard against the alternative shape by taking the max.
        let billedOutput = max(output, reasoning > 0 && output < reasoning ? reasoning : output)
        let cost = CodexPricing.cost(input: input, cachedInput: cached,
                                     output: billedOutput, model: model)

        let rl = payload["rate_limits"] as? [String: Any]
        return (total, cost, rateWindow(rl?["primary"]), rateWindow(rl?["secondary"]))
    }

    private static func rateWindow(_ raw: Any?) -> CodexRateWindow? {
        guard let d = raw as? [String: Any] else { return nil }
        let pct: Double?
        if let v = d["used_percent"] as? Double { pct = v }
        else if let v = d["used_percent"] as? Int { pct = Double(v) }
        else { pct = nil }
        guard let p = pct else { return nil }

        let resets: Date?
        if let n = d["resets_at"] as? Double {
            resets = Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
        } else if let n = d["resets_at"] as? Int {
            let v = Double(n)
            resets = Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v)
        } else { resets = nil }

        return CodexRateWindow(usedPercent: p, resetsAt: resets)
    }
}
