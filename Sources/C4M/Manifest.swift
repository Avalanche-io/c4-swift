import Foundation

/// Represents a complete C4 manifest.
public struct Manifest: Sendable, Codable {

    /// Format version (e.g. "1.0").
    public var version: String

    /// The ordered list of entries.
    public var entries: [Entry]

    /// Base manifest reference (from first-line bare C4 ID).
    public var base: C4ID?

    /// Inline ID lists keyed by sequence C4 ID (bare concatenation).
    public var rangeData: [C4ID: String]

    public init(
        version: String = "1.0",
        entries: [Entry] = [],
        base: C4ID? = nil,
        rangeData: [C4ID: String] = [:]
    ) {
        self.version = version
        self.entries = entries
        self.base = base
        self.rangeData = rangeData
    }

    // MARK: - Entry Management

    /// Append an entry.
    public mutating func addEntry(_ entry: Entry) {
        entries.append(entry)
        invalidateIndex()
    }

    /// Remove an entry by value.
    public mutating func removeEntry(_ entry: Entry) {
        entries.removeAll { $0 == entry }
        invalidateIndex()
    }

    /// Look up an entry by full path (O(1) after index build).
    public func getEntry(path: String) -> Entry? {
        let idx = ensureIndex()
        return idx.byPath[path]
    }

    /// Look up an entry by bare name.
    public func getByName(_ name: String) -> Entry? {
        let idx = ensureIndex()
        return idx.byName[name]
    }

    /// Return the full path of an entry.
    public func entryPath(_ entry: Entry) -> String? {
        let idx = ensureIndex()
        guard let i = idx.entryIndex[entry.indexKey] else { return nil }
        return idx.pathOf[entries[i].indexKeyAt(i)]
    }

    /// Return entries at a given depth.
    public func entriesAtDepth(_ depth: Int) -> [Entry] {
        entries.filter { $0.depth == depth }
    }

    /// Return top-level (depth 0) entries.
    public var root: [Entry] { entriesAtDepth(0) }

    // MARK: - Navigation

    /// Return direct children of an entry.
    public func children(of entry: Entry) -> [Entry] {
        if !entry.isDir { return [] }
        let idx = ensureIndex()
        guard let entryIdx = idx.entryIndex[entry.indexKey] else { return [] }
        guard let childIndices = idx.children[entryIdx] else { return [] }
        return childIndices.map { entries[$0] }
    }

    /// Return the parent directory of an entry.
    public func parent(of entry: Entry) -> Entry? {
        if entry.depth == 0 { return nil }
        let idx = ensureIndex()
        guard let entryIdx = idx.entryIndex[entry.indexKey] else { return nil }
        guard let parentIdx = idx.parent[entryIdx] else { return nil }
        return entries[parentIdx]
    }

    /// Return siblings (entries at the same depth with the same parent).
    public func siblings(of entry: Entry) -> [Entry] {
        let idx = ensureIndex()
        guard let entryIdx = idx.entryIndex[entry.indexKey] else { return [] }
        let parentIdx = idx.parent[entryIdx]

        var siblings: [Entry] = []
        if let pIdx = parentIdx {
            if let childIndices = idx.children[pIdx] {
                for ci in childIndices {
                    if ci != entryIdx {
                        siblings.append(entries[ci])
                    }
                }
            }
        } else {
            // Root level
            for (i, e) in entries.enumerated() {
                if e.depth == 0 && i != entryIdx {
                    siblings.append(e)
                }
            }
        }
        return siblings
    }

    /// Return all ancestors from immediate parent to root.
    public func ancestors(of entry: Entry) -> [Entry] {
        if entry.depth == 0 { return [] }
        let idx = ensureIndex()
        var result: [Entry] = []
        guard var currentIdx = idx.entryIndex[entry.indexKey] else { return [] }
        while let pIdx = idx.parent[currentIdx] {
            result.append(entries[pIdx])
            currentIdx = pIdx
        }
        return result
    }

    /// Return all entries nested under this entry.
    public func descendants(of entry: Entry) -> [Entry] {
        if !entry.isDir { return [] }
        let idx = ensureIndex()
        guard let entryIdx = idx.entryIndex[entry.indexKey] else { return [] }

        var result: [Entry] = []
        func collect(_ parentIndex: Int) {
            guard let childIndices = idx.children[parentIndex] else { return }
            for ci in childIndices {
                result.append(entries[ci])
                if entries[ci].isDir {
                    collect(ci)
                }
            }
        }
        collect(entryIdx)
        return result
    }

    // MARK: - Sorting

    /// Sort all entries: files before directories at same depth, natural sort within.
    public mutating func sortEntries() {
        sortSiblingsHierarchically()
        invalidateIndex()
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

    /// Propagate metadata from children to parents, modifying in place.
    /// Null values stay null. No default mode/size substitution.
    /// Nil-infectious: any null child -> parent is null.
    public mutating func canonicalize() {
        propagateMetadata()
    }

    /// True if any entries have null metadata.
    public var hasNullValues: Bool { entries.contains { $0.hasNullValues } }

    /// Validate the manifest for basic correctness.
    public func validate() throws {
        if version.isEmpty { throw C4MError.invalidEntry(0, "missing version") }

        var seen = Set<String>()
        var dirStack: [String] = []

        for e in entries {
            if e.name.isEmpty { throw C4MError.invalidEntry(0, "empty name") }
            if isPathName(e.name) {
                throw C4MError.pathTraversal(e.name)
            }

            // Build full path
            if e.depth < dirStack.count {
                dirStack = Array(dirStack.prefix(e.depth))
            }
            let fullPath: String
            if !dirStack.isEmpty {
                fullPath = dirStack.joined() + e.name
            } else {
                fullPath = e.name
            }
            if seen.contains(fullPath) { throw C4MError.duplicatePath(fullPath) }
            seen.insert(fullPath)

            if e.isDir {
                while dirStack.count <= e.depth {
                    dirStack.append("")
                }
                dirStack[e.depth] = e.name
            }
        }
    }

    /// Return just the paths from the manifest.
    public var pathList: [String] { entries.map(\.name).sorted() }

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

            // Dedup by name, keeping last occurrence
            var seenNames: [String: Int] = [:]
            var deduped: [(entry: Entry, index: Int)] = []
            for child in children {
                if let idx = seenNames[child.entry.name] {
                    used[deduped[idx].index] = true
                    deduped[idx] = child
                } else {
                    seenNames[child.entry.name] = deduped.count
                    deduped.append(child)
                }
            }
            children = deduped

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

        // Append orphaned entries
        for (i, e) in entries.enumerated() where !used[i] {
            result.append(e)
        }

        entries = result
    }

    // MARK: - Metadata Propagation

    private mutating func propagateMetadata() {
        for i in stride(from: entries.count - 1, through: 0, by: -1) {
            if entries[i].isDir && entries[i].hasNullValues {
                let childIndices = directChildren(of: i)

                // Propagate size (nil-infectious)
                if entries[i].size < 0 {
                    entries[i].size = calculateDirectorySize(childIndices)
                }

                // Propagate timestamp (nil-infectious)
                if entries[i].timestamp == Entry.nullTimestamp {
                    entries[i].timestamp = getMostRecentModtime(childIndices)
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

    /// Nil-infectious: any child with null size -> parent is null.
    /// Includes the byte length of the directory's canonical c4m content.
    private func calculateDirectorySize(_ indices: [Int]) -> Int64 {
        var total: Int64 = 0
        for idx in indices {
            if entries[idx].size < 0 { return -1 }
            total += entries[idx].size
        }
        // Add the byte length of the canonical c4m content for this directory
        for idx in indices {
            let line = entries[idx].canonical
            total += Int64(line.utf8.count) + 1 // +1 for '\n'
        }
        return total
    }

    /// Nil-infectious: any child with null timestamp -> parent is null.
    private func getMostRecentModtime(_ indices: [Int]) -> Date {
        var mostRecent = Date.distantPast
        for idx in indices {
            if entries[idx].timestamp == Entry.nullTimestamp {
                return Entry.nullTimestamp
            }
            if entries[idx].timestamp > mostRecent {
                mostRecent = entries[idx].timestamp
            }
        }
        return mostRecent == Date.distantPast ? Entry.nullTimestamp : mostRecent
    }

    // MARK: - Tree Index

    /// Key type for entries in the index (using array position).
    private struct TreeIndex {
        var byPath: [String: Entry]
        var byName: [String: Entry]
        var pathOf: [String: String]       // indexKey -> fullPath
        var entryIndex: [String: Int]      // indexKey -> entries array index
        var children: [Int: [Int]]         // parent index -> child indices
        var parent: [Int: Int]             // child index -> parent index
    }

    // We use a computed index key that combines index + name for uniqueness
    // This is necessary because Entry is a value type.
    private func ensureIndex() -> TreeIndex {
        var idx = TreeIndex(
            byPath: [:],
            byName: [:],
            pathOf: [:],
            entryIndex: [:],
            children: [:],
            parent: [:]
        )

        // Build entry index mapping
        for (i, e) in entries.enumerated() {
            idx.entryIndex[e.indexKeyAt(i)] = i
            idx.entryIndex[e.indexKey] = i
            idx.byName[e.name] = e
        }

        // Build parent-child relationships
        for (i, e) in entries.enumerated() {
            if e.depth == 0 { continue }
            for j in stride(from: i - 1, through: 0, by: -1) {
                let candidate = entries[j]
                if candidate.depth == e.depth - 1 && candidate.isDir {
                    idx.parent[i] = j
                    idx.children[j, default: []].append(i)
                    break
                }
                if candidate.depth < e.depth - 1 { break }
            }
        }

        // Build paths
        for (i, e) in entries.enumerated() {
            var parts: [String] = []
            var current = i
            parts.append(e.name)
            while let pIdx = idx.parent[current] {
                parts.insert(entries[pIdx].name, at: 0)
                current = pIdx
            }
            let fullPath = parts.joined()
            idx.byPath[fullPath] = e
            idx.pathOf[e.indexKeyAt(i)] = fullPath
        }

        return idx
    }

    private mutating func invalidateIndex() {
        // Value type - index is always rebuilt on access
    }
}

// MARK: - Path Validation

/// Returns true if name contains path semantics (traversal, separators).
func isPathName(_ name: String) -> Bool {
    if name.isEmpty { return true }
    let base = name.hasSuffix("/") ? String(name.dropLast()) : name
    if base.isEmpty { return true }
    if base == "." || base == ".." { return true }
    if base.contains("/") || base.contains("\\") || base.contains("\0") { return true }
    return false
}

// MARK: - Entry Index Key

extension Entry {
    /// A stable key for value-type entries in the tree index.
    var indexKey: String {
        "\(depth):\(name):\(mode.rawValue):\(size)"
    }

    /// A key incorporating the array position for guaranteed uniqueness.
    func indexKeyAt(_ index: Int) -> String {
        "\(index):\(depth):\(name)"
    }
}
