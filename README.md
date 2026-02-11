# C4M

A Swift implementation of the C4 Manifest Format (C4M), as specified in the [C4M v1.0 Specification](https://github.com/Avalanche-io/c4/blob/main/c4m/SPECIFICATION.md).

C4M is a text-based format for describing filesystem contents with content-addressed identification using C4 IDs (SMPTE ST 2114:2017).

## Requirements

- Swift 6.0+
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Avalanche-io/c4m-swift.git", from: "0.1.0"),
]
```

Then add `"C4M"` as a dependency of your target.

## Usage

### Computing C4 IDs

```swift
import C4M

let id = C4ID.identify(data: fileData)
let id2 = C4ID.identify(string: "hello world")
let id3 = try await C4ID.identify(url: fileURL)
```

### Parsing Manifests

```swift
let manifest = try Manifest.unmarshal(c4mString)
for entry in manifest.entries {
    print("\(entry.name): \(entry.size) bytes")
}
```

### Building Manifests

```swift
let manifest = ManifestBuilder()
    .addFile("README.md", mode: .file644, size: 1024, c4id: readmeID)
    .addDir("src/")
        .addFile("main.swift", size: 500)
        .addFile("utils.swift", size: 300)
    .end()
    .build()
```

### Encoding Manifests

```swift
let canonical = manifest.marshal()
let pretty = manifest.marshalPretty()
```

### Operations

```swift
let result = diff(lhs: oldManifest, rhs: newManifest)
let combined = union(manifest1, manifest2)
let common = intersect(manifest1, manifest2)
let trimmed = subtract(removals, from: base)
```

### Sequences

```swift
let seq = try Sequence.parse("frame.[0001-0100].exr")
let files = seq.expand() // ["frame.0001.exr", ..., "frame.0100.exr"]

let collapsed = detectSequences(in: manifest)
```

## License

See LICENSE file.
