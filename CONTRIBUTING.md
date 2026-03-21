# Contributing to c4-swift

Thank you for your interest in contributing to c4-swift. This document covers the project structure, development workflow, and code style expectations.

## Project Structure

```
c4-swift/
  Package.swift              # Swift Package Manager manifest
  Sources/C4M/
    C4ID.swift               # C4 identifier (SHA-512 + base-58)
    Manifest.swift           # Manifest struct, tree index, navigation, validation
    Entry.swift              # Entry struct, FlowDirection, formatting
    FileMode.swift           # Unix file mode parsing and formatting
    Encoder.swift            # C4M text encoder (canonical and pretty)
    Decoder.swift            # C4M text decoder (character-level parser)
    Builder.swift            # Fluent ManifestBuilder / DirBuilder API
    Operations.swift         # Diff, union, intersect, subtract, merge, patch
    SafeName.swift           # Universal Filename Encoding (three-tier)
    Sequence.swift           # Numbered file sequence detection and expansion
    NaturalSort.swift        # Natural sort comparator
    Errors.swift             # C4MError enum
  Tests/C4MTests/
    C4IDTests.swift
    DecoderTests.swift
    EncoderTests.swift
    EntryTests.swift
    FileModeTests.swift
    BuilderTests.swift
    OperationsTests.swift
    SequenceTests.swift
    NaturalSortTests.swift
    Vectors/                 # Cross-language test vectors
```

The package name is `C4`, the library product is `C4`, and the module/target name is `C4M`. Users add `.product(name: "C4", package: "c4-swift")` and write `import C4M`.

## Development Setup

**Requirements**: Swift 6.0+ and Xcode 16+ (or the equivalent Swift toolchain on macOS).

```bash
# Clone
git clone https://github.com/Avalanche-io/c4-swift.git
cd c4-swift

# Build
swift build

# Run tests
swift test
```

All 131 tests should pass. There are no external dependencies to install.

## Code Style

### Value Types and Sendable

Prefer value types (`struct`, `enum`) over reference types. All public types must conform to `Sendable`. The package builds with Swift 6 strict concurrency checking enabled.

If a reference type is necessary (like `ManifestBuilder`), mark it `@unchecked Sendable` and document why a class is needed.

### Swift Naming Conventions

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):

- Types and protocols: `UpperCamelCase`
- Functions, properties, and local variables: `lowerCamelCase`
- Factory methods that return a new value: use naming like `parse(_:)`, `identify(data:)`, not `createFromData`
- Boolean properties: read as assertions (`isDir`, `isNil`, `hasNullValues`)
- Mutating methods on value types: use imperative verbs (`sortEntries()`, `canonicalize()`)
- Non-mutating methods that return a new value: use noun forms or past participles (`sorted()`, `canonical()`)

### Codable and CustomStringConvertible

Types that have a natural string representation should conform to `CustomStringConvertible`. Types that can be serialized to JSON should conform to `Codable`.

### Error Handling

Use `C4MError` for all manifest-related errors. Each case should produce a clear, actionable description via `CustomStringConvertible`.

### Minimalism

The C4 project follows a minimalist philosophy. Before adding a new public API surface, consider whether the functionality can be achieved through composition of existing types. Prefer fewer, well-designed APIs over many convenience wrappers.

### No External Dependencies

This package has zero external dependencies and should stay that way. Only Foundation and CryptoKit (both provided by the platform) are used.

## Testing

Tests use Swift Testing (`import Testing`), not XCTest. Follow existing test patterns:

```swift
import Testing
import Foundation
@testable import C4M

@Suite("Feature Tests")
struct FeatureTests {
    @Test("Description of what this tests")
    func testSomething() throws {
        let result = someOperation()
        #expect(result == expected)
    }
}
```

When adding a new feature, add corresponding tests. When fixing a bug, add a regression test first.

Cross-language test vectors in `Tests/C4MTests/Vectors/` ensure compatibility with the Go reference implementation. If you change encoding or parsing behavior, verify against the vectors.

## Pull Requests

1. Create a branch from `main` for your work.
2. Keep commits focused and messages concise (single line).
3. Ensure all 131+ tests pass with `swift test`.
4. Ensure the build succeeds with `swift build`.
5. Describe what changed and why in the PR description.

For non-trivial changes, open an issue first to discuss the approach.

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 license.
