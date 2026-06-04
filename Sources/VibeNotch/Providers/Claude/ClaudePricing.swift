import Foundation

/// Per-million-token rates for Claude models. `cacheWrite5m` and `cacheWrite1h`
/// are billed differently — the 1h variant is 2x base input vs 1.25x for 5m.
/// Cache reads are the same regardless of TTL.
struct ModelPricing {
    let input: Double
    let output: Double
    let cacheWrite5m: Double
    let cacheWrite1h: Double
    let cacheRead: Double

    /// `bigContext` triggers Sonnet's >200k-token tier (2x rates). Opus and
    /// Haiku don't have a 1M-context tier change — they keep the same rates.
    static func forModel(_ model: String, bigContext: Bool) -> ModelPricing {
        let m = model.lowercased()
        if m.contains("opus") {
            return .init(input: 15, output: 75,
                         cacheWrite5m: 18.75, cacheWrite1h: 30, cacheRead: 1.50)
        }
        if m.contains("haiku") {
            return .init(input: 1, output: 5,
                         cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.10)
        }
        // Sonnet — 1M tier doubles every rate.
        if bigContext {
            return .init(input: 6, output: 22.5,
                         cacheWrite5m: 7.5, cacheWrite1h: 12, cacheRead: 0.60)
        }
        return .init(input: 3, output: 15,
                     cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.30)
    }
}
