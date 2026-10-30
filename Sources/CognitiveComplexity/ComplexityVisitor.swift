import SwiftSyntax

/// Scores one body by SonarSource's Cognitive Complexity (https://www.sonarsource.com/resources/cognitive-complexity/):
///
/// - **+1, plus the current nesting**, for each `if`, `guard`, ternary, `switch`, `for`, `while`, `repeat` and `catch`.
/// - **+1, without nesting**, for each `else if` and `else`.
/// - **+1** for each sequence of like logical operators (`a && b && c` is one, `a && b || c` is two), and for each
///   labeled `break` or `continue`.
/// - **Nesting** goes up inside those structures, and inside closures and nested functions.
///
/// Started from realm/SwiftLint PR #6210, with three differences: logical operators are counted by sequence (the PR
/// counted the lines a condition spans), an `else if` chain doesn't nest deeper with each link, and the tree is
/// operator-folded so ternaries and `&&`/`||` are seen anywhere, not only in `if`/`guard` conditions.
/// Commas in a condition list (`if let a, let b`) aren't counted: they're mostly optional binding.
/// Recursion isn't counted (it needs type information).
public final class ComplexityVisitor: SyntaxVisitor {
    public private(set) var complexity = 0
    private var nesting = 0
    private let closuresNest: Bool

    /// `closuresNest: false` stops closures from adding nesting, for SwiftUI code where every view is a closure.
    public init(closuresNest: Bool = true) {
        self.closuresNest = closuresNest
        super.init(viewMode: .sourceAccurate)
    }

    /// A structure that costs 1 plus its nesting and nests what's inside it.
    private func enterStructure() -> SyntaxVisitorContinueKind {
        complexity += 1 + nesting
        nesting += 1
        return .visitChildren
    }

    private func leaveStructure() { nesting -= 1 }

    // MARK: if / else if / else

    override public func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        if case .codeBlock = node.elseBody { complexity += 1 }   // a final `else`
        if node.isElseIf {
            // Same depth as the `if` that started the chain, which already nested what's inside.
            complexity += 1
            return .visitChildren
        }
        return enterStructure()
    }

    override public func visitPost(_ node: IfExprSyntax) {
        if !node.isElseIf { leaveStructure() }
    }

    // MARK: Other structures

    override public func visit(_: GuardStmtSyntax) -> SyntaxVisitorContinueKind { enterStructure() }
    override public func visitPost(_: GuardStmtSyntax) { leaveStructure() }

    override public func visit(_: TernaryExprSyntax) -> SyntaxVisitorContinueKind { enterStructure() }
    override public func visitPost(_: TernaryExprSyntax) { leaveStructure() }

    override public func visit(_: SwitchExprSyntax) -> SyntaxVisitorContinueKind { enterStructure() }
    override public func visitPost(_: SwitchExprSyntax) { leaveStructure() }

    override public func visit(_: ForStmtSyntax) -> SyntaxVisitorContinueKind { enterStructure() }
    override public func visitPost(_: ForStmtSyntax) { leaveStructure() }

    override public func visit(_: WhileStmtSyntax) -> SyntaxVisitorContinueKind { enterStructure() }
    override public func visitPost(_: WhileStmtSyntax) { leaveStructure() }

    override public func visit(_: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { enterStructure() }
    override public func visitPost(_: RepeatStmtSyntax) { leaveStructure() }

    override public func visit(_: CatchClauseSyntax) -> SyntaxVisitorContinueKind { enterStructure() }
    override public func visitPost(_: CatchClauseSyntax) { leaveStructure() }

    // MARK: Nesting only

    override public func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if closuresNest { nesting += 1 }
        return .visitChildren
    }

    override public func visitPost(_: ClosureExprSyntax) {
        if closuresNest { nesting -= 1 }
    }

    override public func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        nesting += 1
        return .visitChildren
    }

    override public func visitPost(_: FunctionDeclSyntax) { nesting -= 1 }

    // MARK: Breaks in the flow

    override public func visitPost(_ node: InfixOperatorExprSyntax) {
        guard let op = node.logicalOperator else { return }
        // One for each run of the same operator: `a && b && c` is one run, `a && b || c` two.
        if node.parent?.as(InfixOperatorExprSyntax.self)?.logicalOperator != op { complexity += 1 }
    }

    override public func visitPost(_ node: BreakStmtSyntax) {
        if node.label != nil { complexity += 1 }
    }

    override public func visitPost(_ node: ContinueStmtSyntax) {
        if node.label != nil { complexity += 1 }
    }
}

extension IfExprSyntax {
    /// The `if` of an `else if`.
    var isElseIf: Bool {
        guard let parent = parent?.as(IfExprSyntax.self), case .ifExpr(let elseIf) = parent.elseBody else { return false }
        return elseIf.id == id
    }
}

extension InfixOperatorExprSyntax {
    /// `&&` or `||`, if that's the operator.
    var logicalOperator: String? {
        guard let op = `operator`.as(BinaryOperatorExprSyntax.self)?.operator.text, op == "&&" || op == "||" else { return nil }
        return op
    }
}
