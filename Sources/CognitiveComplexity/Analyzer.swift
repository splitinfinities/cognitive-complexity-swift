import SwiftOperators
import SwiftParser
import SwiftSyntax

/// One function-like declaration and its score.
public struct Score: Equatable, Sendable {
    /// The file, as given (the baseline uses it, so pass paths relative to the project).
    public var file: String
    public var line: Int
    public var column: Int
    /// `Type.name(label:)`, `Type.init(_:)`, `Type.body`: stable across edits, so the baseline can match it.
    public var name: String
    public var complexity: Int
    /// `// cognitive-complexity:ignore` above the declaration.
    public var ignored: Bool

    public var baselineKey: String { "\(file)|\(name)" }
}

public enum Analyzer {
    /// Every outermost function, initializer, deinitializer, subscript and computed property (SwiftUI's `body`
    /// included) in `source`. A function nested inside another counts toward the outer one, as in Sonar's metric.
    public static func measure(source: String, file: String, closuresNest: Bool = true) -> [Score] {
        let tree = Parser.parse(source: source)
        // Folding turns `a && b || c` and `x ? y : z` into real expressions, so they're scored wherever they appear.
        let folded = OperatorTable.standardOperators.foldAll(tree) { _ in }
        let converter = SourceLocationConverter(fileName: file, tree: folded)
        let collector = Collector(file: file, converter: converter, closuresNest: closuresNest)
        collector.walk(folded)
        return collector.measurements
    }
}

/// The marker that leaves a declaration out of the report. Write why after it.
public let ignoreMarker = "cognitive-complexity:ignore"

private final class Collector: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    let closuresNest: Bool
    var measurements: [Score] = []
    /// The types we're inside, outermost first.
    private var types: [String] = []

    init(file: String, converter: SourceLocationConverter, closuresNest: Bool) {
        self.file = file
        self.converter = converter
        self.closuresNest = closuresNest
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: Types (for names)

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_: ClassDeclSyntax) { types.removeLast() }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_: StructDeclSyntax) { types.removeLast() }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_: EnumDeclSyntax) { types.removeLast() }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_: ActorDeclSyntax) { types.removeLast() }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_: ProtocolDeclSyntax) { types.removeLast() }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { push(node.extendedType.trimmedDescription) }
    override func visitPost(_: ExtensionDeclSyntax) { types.removeLast() }

    private func push(_ name: String) -> SyntaxVisitorContinueKind {
        types.append(name)
        return .visitChildren
    }

    // MARK: Function-like declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            record(node, name: node.name.text + labels(node.signature.parameterClause.parameters), at: node.name, body: body)
        }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            record(node, name: "init" + labels(node.signature.parameterClause.parameters), at: node.initKeyword, body: body)
        }
        return .skipChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { record(node, name: "deinit", at: node.deinitKeyword, body: body) }
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        if let accessors = node.accessorBlock {
            record(node, name: "subscript" + labels(node.parameterClause.parameters), at: node.subscriptKeyword, body: accessors)
        }
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let accessors = binding.accessorBlock {
                record(node, name: binding.pattern.trimmedDescription, at: binding.pattern, body: accessors)
            } else if let value = binding.initializer?.value {
                // A stored property set up by a closure (`lazy var x = { … }()`) is scored like a computed one.
                let closures = ClosureFinder()
                closures.walk(value)
                if closures.found { record(node, name: binding.pattern.trimmedDescription, at: binding.pattern, body: value) }
            }
        }
        return .skipChildren
    }

    private func labels(_ parameters: FunctionParameterListSyntax) -> String {
        "(" + parameters.map { "\($0.firstName.text):" }.joined() + ")"
    }

    private func record(_ decl: some DeclSyntaxProtocol, name: String, at anchor: some SyntaxProtocol, body: some SyntaxProtocol) {
        let visitor = ComplexityVisitor(closuresNest: closuresNest)
        visitor.walk(body)
        let location = anchor.startLocation(converter: converter)
        measurements.append(Score(
            file: file, line: location.line, column: location.column,
            name: (types + [name]).joined(separator: "."),
            complexity: visitor.complexity,
            ignored: decl.leadingTrivia.description.contains(ignoreMarker)
        ))
    }
}

private final class ClosureFinder: SyntaxVisitor {
    var found = false
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        found = true
        return .skipChildren
    }
}
