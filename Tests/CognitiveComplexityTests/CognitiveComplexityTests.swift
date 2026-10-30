@testable import CognitiveComplexity
import Testing

/// The score of the one declaration in `source`.
private func score(_ source: String, closuresNest: Bool = true) -> Int? {
    let found = Analyzer.measure(source: source, file: "Test.swift", closuresNest: closuresNest)
    return found.count == 1 ? found[0].complexity : nil
}

@Suite struct WhitePaperExamples {
    /// SonarSource's first example: cyclomatic complexity 4, cognitive complexity 7.
    @Test func sumOfPrimesIsSeven() {
        #expect(score("""
        func sumOfPrimes(_ max: Int) -> Int {
            var total = 0
            outer: for i in 1...max {      // +1
                for j in 2..<i {           // +2 (nesting 1)
                    if i % j == 0 {        // +3 (nesting 2)
                        continue outer     // +1
                    }
                }
                total += i
            }
            return total
        }
        """) == 7)
    }

    /// Its second: also cyclomatic 4, but a switch reads as one decision.
    @Test func switchIsOne() {
        #expect(score("""
        func words(_ number: Int) -> String {
            switch number {
            case 1: return "one"
            case 2: return "a couple"
            case 3: return "a few"
            default: return "lots"
            }
        }
        """) == 1)
    }
}

@Suite struct Structures {
    @Test func elseIfChainsDontNestDeeper() {
        // if +1, else if +1, else if +1, else +1, and the `if` inside sits at nesting 1 in any branch: +2.
        #expect(score("""
        func f(a: Bool, b: Bool, c: Bool, d: Bool) {
            if a {
            } else if b {
            } else if c {
                if d {}
            } else {
            }
        }
        """) == 6)
    }

    @Test func logicalOperatorsCountBySequence() {
        #expect(score("func f(a: Bool, b: Bool, c: Bool) { if a && b && c {} }") == 2)
        #expect(score("func f(a: Bool, b: Bool, c: Bool) { if a && b || c {} }") == 3)
        #expect(score("func f(a: Bool, b: Bool, c: Bool, d: Bool) { if a && b, c || d {} }") == 3)
        #expect(score("func f(a: Bool, b: Bool) -> Bool { a || b }") == 1, "outside a condition too")
    }

    @Test func aConditionOnSeveralLinesScoresTheSame() {
        let oneLine = score("func f(a: Bool, b: Bool) { if a && b {} }")
        let twoLines = score("""
        func f(a: Bool, b: Bool) {
            if a
                && b {}
        }
        """)
        #expect(oneLine == 2 && twoLines == 2)
    }

    @Test func eachStructureCostsOne() {
        #expect(score("func f(a: Bool) -> Int { a ? 1 : 2 }") == 1)
        #expect(score("func f(a: Bool) { guard a else { return } }") == 1)
        #expect(score("func f() { do { try g() } catch { } }") == 1)
        #expect(score("func f(a: Bool) { while a {} }") == 1)
        #expect(score("func f(a: Bool) { repeat {} while a }") == 1)
        #expect(score("func f() { let x = 1 }") == 0)
    }

    @Test func closuresAndNestedFunctionsNest() {
        let code = "func f(items: [Bool]) { items.forEach { if $0 {} } }"
        #expect(score(code) == 2)
        #expect(score(code, closuresNest: false) == 1, "SwiftUI mode")
        #expect(score("func f(a: Bool) { func g() { if a {} } }") == 2)
    }
}

@Suite struct Declarations {
    @Test func namesAndKinds() {
        let found = Analyzer.measure(source: """
        struct Card: View {
            var body: some View { if a { Text("") } }
            init(x: Int) {}
            func move(_ id: Int, to lane: Int) {}
            subscript(i: Int) -> Int { 0 }
            lazy var formatter = { if a { 1 } else { 2 } }()
            let stored = 1
        }
        extension Card { func open() {} }
        """, file: "Card.swift")
        #expect(found.map(\.name) == ["Card.body", "Card.init(x:)", "Card.move(_:to:)", "Card.subscript(i:)", "Card.formatter", "Card.open()"])
        #expect(found[0].complexity == 1 && found[0].line == 2)
        #expect(found[4].complexity == 3, "the closure that sets up a lazy property counts: if +2 (inside the closure), else +1")
    }

    @Test func theIgnoreMarker() {
        let found = Analyzer.measure(source: """
        // cognitive-complexity:ignore - a parser; splitting it would hide the grammar
        func parse() {}
        func other() {}
        """, file: "P.swift")
        #expect(found.map(\.ignored) == [true, false])
    }
}

@Suite struct Baselines {
    let limits = Limits(warning: 1, error: 3)

    private func measurement(_ complexity: Int) -> Score {
        Score(file: "A.swift", line: 1, column: 1, name: "A.f()", complexity: complexity, ignored: false)
    }

    @Test func acceptedUntilItGrows() {
        let baseline = Baseline(entries: ["A.swift|A.f()": 3])
        #expect(Report.violations([measurement(3)], limits: limits, baseline: baseline).isEmpty)
        #expect(Report.violations([measurement(2)], limits: limits, baseline: baseline).isEmpty, "better is fine")
        let grown = Report.violations([measurement(4)], limits: limits, baseline: baseline)
        #expect(grown.count == 1 && grown[0].severity == .error && grown[0].baselined == 3)
        #expect(grown[0].formatted(limits: limits).hasSuffix("currently it's 4; it was 3 in the baseline (cognitive_complexity)"))
    }

    @Test func severities() {
        #expect(Report.violations([measurement(1)], limits: limits).isEmpty)
        #expect(Report.violations([measurement(2)], limits: limits).first?.severity == .warning)
        #expect(Report.violations([measurement(4)], limits: limits).first?.severity == .error)
    }
}
