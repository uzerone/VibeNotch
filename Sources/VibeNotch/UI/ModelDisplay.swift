import Foundation

/// Pretty display names for raw model ids, shared by the island card and the
/// menu-bar popover so both always format the same id the same way.
enum ModelDisplay {
    /// "Opus 4.7", "Sonnet 4.6", "Haiku 4.5", "GPT-5.5", "GPT-5.4 mini",
    /// "Codex 5.3", "Codex 5.3 Spark", etc.
    static func displayName(for model: String?) -> String {
        guard let m = model else { return "—" }
        let lower = m.lowercased()
        // OpenAI / Codex models keep their canonical id (don't run the
        // "claude-" strip + version-split path, which would mangle the names).
        if lower.hasPrefix("gpt") || lower.contains("codex") {
            return formatOpenAIModel(lower) ?? m.uppercased()
        }
        // Strip a bracketed capability suffix like "[1m]" before parsing —
        // the 1M-context variant id is "claude-fable-5[1m]", which would
        // otherwise leak into the label as "Fable 5[1m]". The 1M state is
        // already surfaced separately by the "1M" trait chip.
        let base = m.split(separator: "[").first.map(String.init) ?? m
        let parts = base.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
        // Find the family by name, not position: the version can lead the id
        // ("claude-3-5-sonnet" → Sonnet 3.5) or trail it ("claude-opus-4-7" →
        // Opus 4.7). The family is the alphabetic token; the numeric tokens
        // around it are version components (a long run is a date stamp).
        guard let fi = parts.firstIndex(where: { $0.contains(where: \.isLetter) }) else { return m }
        let family = parts[fi]
        let nameCap = family.prefix(1).uppercased() + family.dropFirst()
        // Version digits are the short numeric tokens adjacent to the family,
        // in id order, excluding date stamps (>= 3 digits, e.g. 20241022).
        let versionParts = parts.enumerated()
            .filter { $0.offset != fi && $0.element.allSatisfy(\.isNumber) && $0.element.count < 3 }
            .map(\.element)
        if versionParts.isEmpty { return nameCap }
        return "\(nameCap) \(versionParts.joined(separator: "."))"
    }

    /// Clean labels for OpenAI's Codex CLI lineup. Codex-suffixed coding
    /// models read as "Codex <ver>" (the agentic-coding brand); the rest read
    /// as "GPT-<ver>" with any size suffix kept. `model` is already lowercased.
    ///   gpt-5.5            → "GPT-5.5"
    ///   gpt-5.4-mini       → "GPT-5.4 mini"
    ///   gpt-5.3-codex      → "Codex 5.3"
    ///   gpt-5.3-codex-spark→ "Codex 5.3 Spark"
    static func formatOpenAIModel(_ model: String) -> String? {
        // Pull the version number (e.g. "5.5", "5.4", "5.3") if present.
        let ver = model.split(whereSeparator: { !"0123456789.".contains($0) })
            .first(where: { $0.contains(".") }).map(String.init)

        if model.contains("codex") {
            var label = "Codex"
            if let v = ver { label += " \(v)" }
            if model.contains("spark") { label += " Spark" }
            return label
        }
        if model.hasPrefix("gpt") {
            guard let v = ver else { return model.uppercased() }
            var label = "GPT-\(v)"
            if model.contains("nano") { label += " nano" }
            else if model.contains("mini") { label += " mini" }
            else if model.contains("pro") { label += " Pro" }
            return label
        }
        return nil
    }

    /// Family bucket for the per-model split bar. Claude variants of one
    /// family (opus-4-6, opus-4-7, …) collapse into one label; OpenAI / Codex
    /// models stay distinct per model (GPT-5.5, Codex 5.3, …).
    static func familyLabel(for model: String) -> String {
        let m = model.lowercased()
        if m.contains("fable") || m.contains("mythos") { return "Fable" }
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.hasPrefix("gpt") || m.contains("codex") {
            return formatOpenAIModel(m) ?? "GPT"
        }
        return "Other"
    }

    /// Reverse of `familyLabel` — gives `ModelDot.colorForModel` a string it
    /// recognizes so a split-bar segment's color matches the model dot. Any
    /// OpenAI family resolves to a gpt id, which `colorForModel` tints teal.
    static func idForFamily(_ family: String) -> String {
        switch family {
        case "Fable":   return "claude-fable"
        case "Opus":    return "claude-opus"
        case "Sonnet":  return "claude-sonnet"
        case "Haiku":   return "claude-haiku"
        default:
            let f = family.lowercased()
            if f.hasPrefix("gpt") || f.contains("codex") { return "gpt-5.5" }
            return "claude-other"
        }
    }
}
