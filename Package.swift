// swift-tools-version: 6.0
import PackageDescription

/// Cognitive complexity (SonarSource's metric) for lint, until SwiftLint ships the rule
/// (realm/SwiftLint#3335; the visitor started from PR #6210). Its own package so swift-syntax stays out of the projects that use it.
let package = Package(
    name: "CognitiveComplexity",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cognitive-complexity", targets: ["cognitive-complexity"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
    ],
    targets: [
        .target(name: "CognitiveComplexity", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftOperators", package: "swift-syntax"),
        ]),
        .executableTarget(name: "cognitive-complexity", dependencies: ["CognitiveComplexity"]),
        .testTarget(name: "CognitiveComplexityTests", dependencies: ["CognitiveComplexity"]),
    ]
)
