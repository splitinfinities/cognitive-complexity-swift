import CognitiveComplexity
import Foundation

let usage = """
usage: cognitive-complexity [options] <path>...

Cognitive complexity (SonarSource) of every function, initializer, subscript and computed property in the
Swift files under each path, reported like SwiftLint. Exits 2 if anything is over the error limit.

  --warning N              warn above N (default 15)
  --error N                error above N (default 25)
  --limit PATH=W,E         other limits for files whose path contains PATH (repeatable; the longest match wins)
  --no-closure-nesting     closures don't add nesting (SwiftUI code); default: they do
  --no-closure-nesting-in PATH   the same, only for files whose path contains PATH (repeatable)
  --baseline FILE          accept what FILE lists, unless it has grown
  --write-baseline FILE    write everything over the warning limit to FILE, and report nothing
  --exclude PATH           skip files whose path contains PATH (repeatable; .build is always skipped)
  --summary                print percentiles and the highest scores instead of violations
"""

var limits = Limits(warning: 15, error: 25)
var overrides: [(path: String, limits: Limits)] = []
var closuresNest = true
var flatClosurePaths: [String] = []
var baselineURL: URL?
var writeBaselineURL: URL?
var excludes = [".build/", "/build/"]
var summary = false
var paths: [String] = []

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n\n\(usage)\n".utf8))
    exit(64)
}

var arguments = CommandLine.arguments.dropFirst()
@MainActor func value(_ flag: String) -> String {
    guard let v = arguments.popFirst() else { fail("\(flag) needs a value") }
    return v
}
@MainActor func number(_ flag: String) -> Int {
    guard let n = Int(value(flag)) else { fail("\(flag) needs a number") }
    return n
}
@MainActor func limitsValue(_ text: String) -> Limits {
    let parts = text.split(separator: ",").compactMap { Int($0) }
    guard parts.count == 2 else { fail("limits are WARNING,ERROR, e.g. 15,25") }
    return Limits(warning: parts[0], error: parts[1])
}

while let arg = arguments.popFirst() {
    switch arg {
    case "--warning": limits.warning = number(arg)
    case "--error": limits.error = number(arg)
    case "--limit":
        let spec = value(arg).split(separator: "=", maxSplits: 1).map(String.init)
        guard spec.count == 2 else { fail("--limit is PATH=WARNING,ERROR") }
        overrides.append((spec[0], limitsValue(spec[1])))
    case "--no-closure-nesting": closuresNest = false
    case "--no-closure-nesting-in": flatClosurePaths.append(value(arg))
    case "--baseline": baselineURL = URL(fileURLWithPath: value(arg))
    case "--write-baseline": writeBaselineURL = URL(fileURLWithPath: value(arg))
    case "--exclude": excludes.append(value(arg))
    case "--summary": summary = true
    case "-h", "--help": print(usage); exit(0)
    default:
        if arg.hasPrefix("-") { fail("unknown option \(arg)") }
        paths.append(arg)
    }
}
guard !paths.isEmpty else { fail("no paths given") }

/// The limits for one file.
@MainActor func limits(for file: String) -> Limits {
    overrides.filter { file.contains($0.path) }.max { $0.path.count < $1.path.count }?.limits ?? limits
}

// Swift files under each path, relative as given, in a stable order.
var files: [String] = []
for path in paths {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { fail("no such path: \(path)") }
    if !isDirectory.boolValue {
        files.append(path)
        continue
    }
    let enumerator = FileManager.default.enumerator(atPath: path)
    while let item = enumerator?.nextObject() as? String {
        if item.hasSuffix(".swift") { files.append((path as NSString).appendingPathComponent(item)) }
    }
}
files = files.filter { file in !excludes.contains { file.contains($0) } }.sorted()

var measurements: [Score] = []
for file in files {
    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
    let nest = closuresNest && !flatClosurePaths.contains { file.contains($0) }
    measurements += Analyzer.measure(source: source, file: file, closuresNest: nest)
}

if summary {
    print(Report.summary(measurements))
    exit(0)
}

if let writeBaselineURL {
    var baseline = Baseline()
    for m in measurements where !m.ignored && m.complexity > limits(for: m.file).warning {
        baseline.entries[m.baselineKey] = m.complexity
    }
    do { try baseline.write(writeBaselineURL) } catch { fail("couldn't write \(writeBaselineURL.path): \(error)") }
    print("Wrote \(baseline.entries.count) declarations to \(writeBaselineURL.path)")
    exit(0)
}

var baseline = Baseline()
if let baselineURL, FileManager.default.fileExists(atPath: baselineURL.path) {
    do { baseline = try Baseline.load(baselineURL) } catch { fail("couldn't read \(baselineURL.path): \(error)") }
}

var errors = 0
for m in measurements {
    let fileLimits = limits(for: m.file)
    for violation in Report.violations([m], limits: fileLimits, baseline: baseline) {
        print(violation.formatted(limits: fileLimits))
        if violation.severity == .error { errors += 1 }
    }
}
exit(errors > 0 ? 2 : 0)
