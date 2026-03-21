# c4-swift

[![Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](./LICENSE)
[![Swift 6.0+](https://img.shields.io/badge/swift-6.0+-F05138.svg)](https://swift.org)
[![Tests](https://img.shields.io/badge/tests-131-brightgreen.svg)](./Tests)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20|%20iOS%20|%20tvOS%20|%20watchOS%20|%20visionOS-lightgrey.svg)](#compatibility)

Swift-native [C4](https://github.com/Avalanche-io/c4) content identification for Apple platforms. Zero dependencies. `Sendable` throughout. Built on CryptoKit.

```swift
import C4M

// Identify any content -- same bytes always produce the same 90-character ID
let id = C4ID.identify(string: "hello world")
// c41yP4cqy7jmaRDzC2bmcGNZkuQb3VdftMk6YH7ynQ2Qw4zktKsyA9fk52xghNQNAdkpF9iFmFkKh2bNVG4kDWhsok

// Parse a c4m file describing a delivery
let manifest = try Manifest.unmarshal(c4mText)
for entry in manifest.entries {
    print("\(entry.name) \(entry.size) bytes \(entry.c4id?.string ?? "-")")
}

// Diff two snapshots to find what changed
let changes = diff(lhs: lastWeek, rhs: today)
print("+\(changes.added.entries.count) -\(changes.removed.entries.count) ~\(changes.modified.entries.count)")
```

## Install

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Avalanche-io/c4-swift.git", from: "1.0.5"),
]
```

Then add the dependency to your target:

```swift
.target(name: "YourTarget", dependencies: [
    .product(name: "C4", package: "c4-swift"),
]),
```

Import the module:

```swift
import C4M
```

## What is C4?

C4 IDs are universally unique, unforgeable identifiers derived from content using SHA-512. They are standardized as [SMPTE ST 2114:2017](https://ieeexplore.ieee.org/document/7971777). Same content always produces the same 90-character ID, regardless of filename, location, or time.

```swift
let id = C4ID.identify(data: fileData)
// c45xZeXwMSpqJtNFjR3DRCV5hR7xeYHjqFsXdE1CJKB15gsHYsTPIwHmYTtsjkswjxOeIwMRxyg3JVk4rq6WuhVog
```

## C4M Format

A **c4m file** is a human-readable text file that describes a filesystem. It captures file names, sizes, permissions, timestamps, and C4 IDs in a format you can read, edit, diff, and email.

```
-rw-r--r-- 2025-06-15T12:00:00Z      3 README.md   c45xZeXwMSpq...
drwxr-xr-x 2025-06-15T12:00:00Z      3 src/        -
  -rw-r--r-- 2025-06-15T12:00:00Z    3 main.swift  c45KgBYEvEE7...
```

A 2 KB c4m file can describe an 8 TB project. Compare two c4m files to find exactly which frames changed across a delivery -- in seconds, not hours.

## API

### C4ID

Content identification built on SHA-512 and base-58 encoding.

```swift
// Identify content
let id = C4ID.identify(data: rawBytes)
let id = C4ID.identify(string: "hello world")
let id = try await C4ID.identify(url: fileURL)

// Parse a C4 ID string
if let id = C4ID("c41yP4cqy7jmaRDzC2bmcGNZkuQb3VdftMk6YH7ynQ2Qw4zktKsyA9fk52xghNQNAdkpF9iFmFkKh2bNVG4kDWhsok") {
    print(id.string)    // 90-character string representation
    print(id.digest)    // raw 64-byte SHA-512 digest
    print(id.isNil)     // false (true only for the all-zero void ID)
}

// The void (nil) ID
let void = C4ID.void   // all-zero digest

// C4IDs are Comparable, Hashable, Codable, and CustomStringConvertible
let sorted = [idA, idB, idC].sorted()
let lookup: [C4ID: String] = [id: "readme.txt"]
let json = try JSONEncoder().encode(id)
```

### Manifest

Parse, encode, query, and compute the identity of c4m files.

```swift
// Parse from string or data
let manifest = try Manifest.unmarshal(c4mString)
let manifest = try Manifest.unmarshal(c4mData)

// Encode to c4m text
let text = manifest.marshal()          // standard c4m text format
let pretty = manifest.marshalPretty()  // aligned columns, comma-separated sizes

// Compute the C4 ID of the manifest itself
let manifestID = manifest.computeC4ID()

// Sort entries (files before directories, natural sort within each level)
var m = manifest
m.sortEntries()

// Canonicalize (propagate metadata from children to parents)
m.canonicalize()

// Validate for structural correctness
try manifest.validate()  // throws on duplicate paths, traversal attacks, etc.

// Query
let readme = manifest.getEntry(path: "src/README.md")
let byName = manifest.getByName("README.md")
let topLevel = manifest.root
let atDepth2 = manifest.entriesAtDepth(2)
let paths = manifest.pathList
```

### Entry

Each entry in a manifest represents a file, directory, symlink, or sequence.

```swift
let entry = Entry(
    mode: .file644,
    timestamp: Date(),
    size: 4096,
    name: "render.exr",
    c4id: someID
)

// Properties
entry.isDir          // true if directory (mode or trailing slash)
entry.isSymlink      // true if symbolic link
entry.isFlowLinked   // true if flow link declared
entry.isSequence     // true if sequence notation
entry.hasNullValues  // true if any metadata is null/unspecified
entry.depth          // nesting level (0 = top level)

// Formatting
entry.canonical      // canonical single-line representation
entry.format(indentWidth: 2, displayFormat: true)  // human-readable with indentation
```

### FileMode

Unix file mode (type + permission bits) with parsing and formatting.

```swift
// Common presets
FileMode.file644      // -rw-r--r--
FileMode.file755      // -rwxr-xr-x
FileMode.dir755       // drwxr-xr-x
FileMode.symlink777   // lrwxrwxrwx
FileMode.null         // unspecified

// Parse from string
let mode = FileMode(string: "-rw-r--r--")
let dir  = FileMode(string: "drwxr-xr-x")

// Queries
mode?.isDir           // false
mode?.isRegular       // true
mode?.isSymlink       // false
mode?.permissions     // 0o644
mode?.description     // "-rw-r--r--"
```

### Builder

Fluent API for constructing manifests programmatically.

```swift
let manifest = ManifestBuilder()
    .addFile("README.md", mode: .file644, size: 1024, c4id: readmeID)
    .addFile("Makefile", mode: .file644, size: 256)
    .addDir("src")
        .addFile("main.swift", mode: .file644, size: 500)
        .addFile("utils.swift", mode: .file644, size: 300)
        .addDir("internal")
            .addFile("helper.swift", size: 128)
        .endDir()
    .end()
    .addDir("tests")
        .addFile("test_main.swift", size: 400)
    .end()
    .build()
```

The builder automatically handles directory naming (appends `/` if missing) and nesting depth. `DirBuilder.addDir()` returns a nested `DirBuilder`; call `.endDir()` to return to the parent directory or `.end()` to return to the root `ManifestBuilder`.

### Diff / Union / Intersect / Subtract

Set operations on manifests.

```swift
// Diff: compare two manifests
let result = diff(lhs: oldManifest, rhs: newManifest)
result.added      // entries only in rhs
result.removed    // entries only in lhs
result.modified   // same path, different content or metadata
result.same       // identical entries
result.isEmpty    // true if no differences

// Union: combine manifests, keeping the latest version of each path
let combined = union(manifest1, manifest2, manifest3)

// Intersect: entries whose paths exist in all manifests
let common = intersect(manifest1, manifest2)

// Subtract: remove entries by path
let trimmed = subtract(removals, from: base)
```

### Three-Way Merge

Merge diverged manifest states against a common ancestor.

```swift
let result = merge(base: ancestor, local: myChanges, remote: theirChanges)

// The merged manifest
let merged = result.merged

// Any conflicts that could not be auto-resolved
for conflict in result.conflicts {
    print("Conflict at \(conflict.path)")
    print("  base:   \(conflict.baseEntry?.name ?? "nil")")
    print("  local:  \(conflict.localEntry?.name ?? "nil")")
    print("  remote: \(conflict.remoteEntry?.name ?? "nil")")
}
```

The merge follows standard three-way semantics: unchanged entries pass through, single-side changes win, and both-sides-changed produces a conflict (resolved by most recent timestamp, but still reported).

### Patch Chains

C4m files can contain version histories as patch chains. Each patch section is separated by a bare C4 ID checkpoint that must match the accumulated state.

```swift
// Parse a c4m file with embedded patches (decoded automatically)
let manifest = try Manifest.unmarshal(chainedC4MText)

// Apply a patch to a base manifest
let updated = applyPatch(base: original, patch: changes)
```

Patch semantics: an entry identical to the base means removal; a new entry means addition; a different entry at the same path means modification.

### SafeName

Universal Filename Encoding for safe representation of any filesystem name.

```swift
// Encode a raw filename to safe representation
let safe = safeName("file\twith\ttabs.txt")     // "file\\twith\\ttabs.txt"
let safe = safeName("file\0with\0nulls.txt")     // "file\\0with\\0nulls.txt"

// Decode back to original
let raw = unsafeName(safe)                        // original bytes restored
```

Three-tier encoding:
- **Tier 1**: Printable UTF-8 passes through unchanged
- **Tier 2**: Backslash escapes for common control characters (`\0`, `\t`, `\n`, `\r`, `\\`)
- **Tier 3**: Braille-encoded byte sequences delimited by the currency sign for all other non-printable bytes

### Sequences

Detect and work with numbered file sequences (common in VFX/animation pipelines).

```swift
// Parse a sequence pattern
let seq = try Sequence.parse("frame.[0001-0100].exr")
seq.prefix    // "frame."
seq.suffix    // ".exr"
seq.padding   // 4
seq.count     // 100

// Expand to individual filenames
let files = seq.expand()   // ["frame.0001.exr", "frame.0002.exr", ..., "frame.0100.exr"]

// Check if a frame is in the sequence
seq.contains(frame: 50)    // true
seq.contains(frame: 200)   // false

// Ranges with step notation
let stepped = try Sequence.parse("render.[0001-0100:2].exr")  // every other frame

// Detect sequences in a manifest (collapse numbered runs into sequence entries)
let collapsed = detectSequences(in: manifest, minLength: 3)

// Utility functions
isSequencePattern("frame.[0001-0100].exr")    // true
let names = try expandSequencePattern("shot.[001-010].dpx")
```

### Tree Navigation

Navigate the manifest's hierarchical structure.

```swift
let manifest = try Manifest.unmarshal(text)

if let srcDir = manifest.getByName("src/") {
    // Direct children
    let files = manifest.children(of: srcDir)

    // Parent directory
    let parent = manifest.parent(of: srcDir)

    // Sibling entries (same level, same parent)
    let siblings = manifest.siblings(of: srcDir)

    // All ancestors from immediate parent to root
    let ancestors = manifest.ancestors(of: someDeepEntry)

    // All entries nested under a directory (recursive)
    let allFiles = manifest.descendants(of: srcDir)
}

// Entries at a specific depth
let topLevel = manifest.entriesAtDepth(0)
let nested = manifest.entriesAtDepth(2)
```

### Flow Links and Hard Links

C4m entries can declare flow links (directional sync relationships) and hard links.

```swift
// Flow link directions
FlowDirection.outbound       // -> content here propagates there
FlowDirection.inbound        // <- content there propagates here
FlowDirection.bidirectional  // <> bidirectional sync

// Check entries
entry.isFlowLinked           // true if any flow direction is set
entry.flowDirection          // the FlowDirection enum value
entry.flowTarget             // e.g. "studio:inbox/"

// Hard links
entry.hardLink               // 0=none, -1=ungrouped (->), >0=group number (->N)
```

## Sendable and Concurrency

All public types conform to `Sendable` and are safe for use with Swift 6 strict concurrency:

- `C4ID`, `Entry`, `FileMode`, `Sequence`, `SequenceRange`, `FlowDirection` -- value types, fully `Sendable`
- `Manifest` -- value type, fully `Sendable`
- `Encoder`, `Decoder` -- value types, fully `Sendable`
- `ManifestBuilder`, `DirBuilder` -- reference types, `@unchecked Sendable`
- `DiffResult`, `MergeResult`, `MergeConflict` -- value types, fully `Sendable`
- `C4MError` -- enum, fully `Sendable`

The async `C4ID.identify(url:)` method integrates naturally with structured concurrency.

## Works With

c4-swift is part of the [C4 ecosystem](https://github.com/Avalanche-io/c4):

- **[c4](https://github.com/Avalanche-io/c4)** -- Go CLI and library for identification and content storage
- **[c4py](https://github.com/Avalanche-io/c4py)** -- Pure Python C4 implementation
- **[c4sh](https://github.com/Avalanche-io/c4sh)** -- Shell integration for c4m files
- **[c4git](https://github.com/Avalanche-io/c4git)** -- Git clean/smudge filter for large media assets
- **[c4d](https://github.com/Avalanche-io/c4d)** -- C4 daemon for peer-to-peer content distribution

All implementations produce identical C4 IDs for the same content. A c4m file generated by the Go CLI, parsed by Python, and verified by Swift will agree on every ID.

## Compatibility

Cross-language test vectors ensure c4-swift produces byte-identical output to the [Go reference implementation](https://github.com/Avalanche-io/c4). The test suite covers:

- C4 ID computation and base-58 encoding/decoding
- C4m parsing and encoding round-trips
- Natural sort order
- Sequence detection and expansion
- Diff, union, intersect, subtract, and three-way merge
- Patch chain application
- SafeName encoding/decoding

131 tests across 9 test suites, all passing.

**Requirements**: Swift 6.0+, macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+

**Dependencies**: None. Uses only Foundation and CryptoKit (both ship with every Apple platform).

## License

Apache 2.0 -- see [LICENSE](./LICENSE).
