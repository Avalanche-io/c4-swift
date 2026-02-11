import Foundation

/// The canonical C4M timestamp format.
public let timestampFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"

/// Represents a complete C4 manifest.
public struct Manifest: Sendable, Codable {

    /// Format version (e.g. "1.0").
    public var version: String

    /// The ordered list of entries.
    public var entries: [Entry]

    /// Base manifest reference (for layered manifests).
    public var base: C4ID

    /// Layer metadata.
    public var layers: [Layer]

    /// Application-specific metadata reference.
    public var data: C4ID

    public init(
        version: String = "1.0",
        entries: [Entry] = [],
        base: C4ID = .void,
        layers: [Layer] = [],
        data: C4ID = .void
    ) {
        self.version = version
        self.entries = entries
        self.base = base
        self.layers = layers
        self.data = data
    }

    // MARK: - Entry Management

    /// Append an entry.
    public mutating func addEntry(_ entry: Entry) {
        entries.append(entry)
    }

    /// Look up an entry by name. O(n) scan.
    public func getEntry(path: String) -> Entry? {
        entries.first { $0.name == path }
    }

    /// Return entries at a given depth.
    public func entriesAtDepth(_ depth: Int) -> [Entry] {
        entries.filter { $0.depth == depth }
    }

    /// Return top-level (depth 0) entries.
    public var root: [Entry] { entriesAtDepth(0) }

    // MARK: - Sorting

    /// Sort all entries: files before directories at same depth, natural sort within.
    public mutating func sortEntries() {
        sortSiblingsHierarchically()
    }

    // MARK: - Canonical Form

    /// Produce the canonical string for C4 ID computation.
    public func canonical() -> String {
        guard let minDepth = entries.map(\.depth).min() else { return "" }

        let topLevel = entries.filter { $0.depth == minDepth }
            .sorted { a, b in
                let aIsDir = a.name.hasSuffix("/")
                let bIsDir = b.name.hasSuffix("/")
                if aIsDir != bIsDir { return !aIsDir }
                return naturalLess(a.name, b.name)
            }

        var buf = ""
        for entry in topLevel {
            buf += entry.canonical
            buf += "\n"
        }
        return buf
    }

    /// Compute the C4 ID of this manifest's canonical form.
    public func computeC4ID() -> C4ID {
        var copy = self
        copy.canonicalize()
        let text = copy.canonical()
        return C4ID.identify(string: text)
    }

    /// Resolve null values to explicit defaults, modifying in place.
    public mutating func canonicalize() {
        propagateMetadata()
        for i in entries.indices {
            if entries[i].mode.isNull {
                if entries[i].isDir {
                    entries[i].mode = .dir755
                } else {
                    entries[i].mode = .file644
                }
            }
            if entries[i].size < 0 {
                entries[i].size = 0
            }
        }
    }

    /// Deep copy.
    public func copy() -> Manifest { self }

    /// True if any entries have null metadata.
    public var hasNullValues: Bool { entries.contains { $0.hasNullValues } }

    /// Validate the manifest for basic correctness.
    public func validate() throws {
        if version.isEmpty { throw C4MError.invalidHeader("missing version") }
        var seen = Set<String>()
        for e in entries {
            if e.name.isEmpty { throw C4MError.invalidEntry(0, "empty name") }
            if e.name.contains("../") || e.name.contains("./") {
                throw C4MError.pathTraversal(e.name)
            }
            if seen.contains(e.name) { throw C4MError.duplicatePath(e.name) }
            seen.insert(e.name)
        }
    }

    /// Return just the paths from the manifest.
    public var pathList: [String] { entries.map(\.name).sorted() }

    /// Paths queued for removal in @remove layers.
    public var removals: [String] { entries.filter(\.inRemoveLayer).map(\.name) }

    // MARK: - Hierarchical Sort

    private mutating func sortSiblingsHierarchically() {
        guard !entries.isEmpty else { return }

        var result: [Entry] = []
        result.reserveCapacity(entries.count)
        var used = [Bool](repeating: false, count: entries.count)

        func processLevel(parentIdx: Int, parentDepth: Int) {
            let childDepth = parentDepth + 1
            let startIdx = parentIdx == -1 ? 0 : parentIdx + 1
            let effectiveChildDepth = parentIdx == -1 ? 0 : childDepth

            var children: [(entry: Entry, index: Int)] = []
            for i in startIdx ..< entries.count {
                if used[i] { continue }
                if entries[i].depth < effectiveChildDepth { break }
                if entries[i].depth > effectiveChildDepth { continue }
                children.append((entries[i], i))
            }

            children.sort { a, b in
                if a.entry.isDir != b.entry.isDir { return !a.entry.isDir }
                return naturalLess(a.entry.name, b.entry.name)
            }

            for child in children {
                used[child.index] = true
                result.append(child.entry)
                if child.entry.isDir {
                    processLevel(parentIdx: child.index, parentDepth: child.entry.depth)
                }
            }
        }

        processLevel(parentIdx: -1, parentDepth: -1)

        // Append any orphaned entries
        for (i, e) in entries.enumerated() where !used[i] {
            result.append(e)
        }

        entries = result
    }

    // MARK: - Metadata Propagation

    private mutating func propagateMetadata() {
        for i in stride(from: entries.count - 1, through: 0, by: -1) {
            if entries[i].isDir && entries[i].hasNullValues {
                let children = directChildren(of: i)
                if entries[i].size < 0 {
                    entries[i].size = children.reduce(0) { $0 + max(0, entries[$1].size) }
                }
                if entries[i].timestamp == Entry.nullTimestamp {
                    let latest = children.compactMap { idx -> Date? in
                        let t = entries[idx].timestamp
                        return t == Entry.nullTimestamp ? nil : t
                    }.max()
                    entries[i].timestamp = latest ?? Entry.nullTimestamp
                }
            }
        }
    }

    private func directChildren(of parentIndex: Int) -> [Int] {
        let parentDepth = entries[parentIndex].depth
        var result: [Int] = []
        for j in (parentIndex + 1) ..< entries.count {
            if entries[j].depth == parentDepth + 1 {
                result.append(j)
            } else if entries[j].depth <= parentDepth {
                break
            }
        }
        return result
    }
}

/// Layer type: add or remove.
public enum LayerType: Int, Sendable, Codable {
    case add = 0
    case remove = 1
}

/// Layer metadata for a changeset.
public struct Layer: Sendable, Codable, Hashable {
    public var type: LayerType
    public var by: String
    public var time: Date?
    public var note: String
    public var data: C4ID

    public init(
        type: LayerType = .add,
        by: String = "",
        time: Date? = nil,
        note: String = "",
        data: C4ID = .void
    ) {
        self.type = type
        self.by = by
        self.time = time
        self.note = note
        self.data = data
    }
}
