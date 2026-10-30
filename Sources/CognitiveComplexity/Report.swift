import Foundation

/// The limits: over `warning` is a warning, over `error` an error (SwiftLint's convention for metrics).
public struct Limits: Sendable {
    public var warning: Int
    public var error: Int
    public init(warning: Int, error: Int) {
        self.warning = warning
        self.error = error
    }
}

/// Declarations already over the limit when the baseline was written, with their score then.
///
/// Unlike SwiftLint's baseline, an entry keeps its score: a baselined function is only accepted while it doesn't
/// get worse. Keys are `file|Type.name(labels:)`, so moving code around a file doesn't break the match.
public struct Baseline: Codable, Sendable {
    public var entries: [String: Int]

    public init(entries: [String: Int] = [:]) { self.entries = entries }

    public static func load(_ url: URL) throws -> Baseline {
        try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }

    public func write(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public struct Violation: Equatable, Sendable {
    public enum Severity: String, Sendable { case warning, error }
    public var measurement: Score
    public var severity: Severity
    /// The score in the baseline, when it has grown since.
    public var baselined: Int?

    /// SwiftLint's format, which Xcode and editors turn into issues.
    public func formatted(limits: Limits) -> String {
        let m = measurement
        let was = baselined.map { "; it was \($0) in the baseline" } ?? ""
        return "\(m.file):\(m.line):\(m.column): \(severity.rawValue): Cognitive Complexity Violation: "
            + "\(m.name) should have cognitive complexity \(limits.warning) or less; currently it's \(m.complexity)\(was) (cognitive_complexity)"
    }
}

public enum Report {
    /// What's over the limits and not accepted by the baseline (or has grown past its baseline score).
    public static func violations(_ measurements: [Score], limits: Limits, baseline: Baseline = Baseline()) -> [Violation] {
        measurements.compactMap { m in
            guard !m.ignored, m.complexity > limits.warning else { return nil }
            let known = baseline.entries[m.baselineKey]
            if let known, m.complexity <= known { return nil }
            return Violation(measurement: m, severity: m.complexity > limits.error ? .error : .warning, baselined: known)
        }
    }

    /// Percentiles and the worst declarations, for choosing limits.
    public static func summary(_ measurements: [Score], top: Int = 15) -> String {
        let scores = measurements.map(\.complexity).sorted()
        guard !scores.isEmpty else { return "No declarations found." }
        func percentile(_ p: Double) -> Int { scores[min(scores.count - 1, Int(Double(scores.count) * p))] }
        var lines = ["\(scores.count) declarations: median \(percentile(0.5)), 90% \(percentile(0.9)), 95% \(percentile(0.95)), "
            + "99% \(percentile(0.99)), max \(scores.last!)"]
        for limit in [10, 15, 20, 25, 30] {
            lines.append("  over \(limit): \(scores.filter { $0 > limit }.count)")
        }
        lines.append("Highest:")
        for m in measurements.sorted(by: { $0.complexity > $1.complexity }).prefix(top) {
            lines.append(String(format: "%5d  ", m.complexity) + "\(m.name)  \(m.file):\(m.line)")
        }
        return lines.joined(separator: "\n")
    }
}
