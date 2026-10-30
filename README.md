# cognitive-complexity-swift

[Cognitive complexity](https://www.sonarsource.com/resources/cognitive-complexity/) for Swift, reported in
SwiftLint's format so Xcode shows the warnings the same way.

It scores how hard code is to follow, where cyclomatic complexity counts the paths through it. A `switch` costs 1
however many cases it has. An `if` costs more the deeper it's nested. Each `else if` and `else` costs 1, and so does
each run of `&&` or `||`.

SwiftLint doesn't have the rule yet. It was requested in
[realm/SwiftLint#3335](https://github.com/realm/SwiftLint/issues/3335) and has two open PRs, #5838 and #6210. This
is a small SwiftSyntax package whose visitor started from #6210, to use until one of them is merged.

## Usage

```sh
swift build -c release
.build/release/cognitive-complexity --warning 10 --error 20 Sources
```

```
usage: cognitive-complexity [options] <path>...

  --warning N              warn above N (default 15)
  --error N                error above N (default 25)
  --limit PATH=W,E         other limits for files whose path contains PATH (repeatable; the longest match wins)
  --no-closure-nesting     closures don't add nesting (SwiftUI code); default: they do
  --no-closure-nesting-in PATH   the same, only for files whose path contains PATH (repeatable)
  --baseline FILE          accept what FILE lists, unless it has grown
  --write-baseline FILE    write everything over the warning limit to FILE, and report nothing
  --exclude PATH           skip files whose path contains PATH (repeatable; .build is always skipped)
  --summary                print percentiles and the highest scores instead of violations
```

It exits 2 if anything is over the error limit.

- **Baseline:** a listed declaration is only accepted while its score doesn't go up. If it gets worse, it's
  reported along with its old score.
- **Exceptions:** put `// cognitive-complexity:ignore - <why>` on the line above a declaration.
- **SwiftUI:** every `Section { HStack { … } }` is a closure, so for view code pass `--no-closure-nesting-in` with
  the views folder. Elsewhere closures nest, as the white paper specifies.
- **Not counted:** recursion (it needs type information), and commas in a condition list, which are mostly
  `if let a, let b`.

## Fixes compared with #6210

- `&&`/`||` are counted by run of the same operator. The PR counted the lines a condition spans, so splitting a
  condition across lines raised its score.
- An `else if` chain doesn't nest deeper with every link.
- Ternaries and logical operators count anywhere, not only in `if`/`guard` conditions.
- Computed properties are measured, including SwiftUI's `var body`, which the PR skipped.
- The white paper's own examples (scores 7 and 1) are among its tests.

## Tests

```sh
swift test
```
