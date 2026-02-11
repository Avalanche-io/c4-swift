import Foundation

/// Result of comparing two manifests.
public struct DiffResult: Sendable {
    /// Entries present only in the right-hand manifest.
    public var added: Manifest
    /// Entries present only in the left-hand manifest.
    public var removed: Manifest
    /// Entries present in both but with different content or metadata.
    public var modified: Manifest
    /// Entries identical in both.
    public var same: Manifest

    /// True if there are no differences.
    public var isEmpty: Bool {
        added.entries.isEmpty && removed.entries.isEmpty && modified.entries.isEmpty
    }
}

/// Compare two manifests and return adds, removes, modifications, and identical entries.
public func diff(lhs: Manifest, rhs: Manifest) -> DiffResult {
    var result = DiffResult(
        added: Manifest(),
        removed: Manifest(),
        modified: Manifest(),
        same: Manifest()
    )

    let aMap = Dictionary(lhs.entries.map { ($0.name, $0) }, uniquingKeysWith: { _, b in b })
    let bMap = Dictionary(rhs.entries.map { ($0.name, $0) }, uniquingKeysWith: { _, b in b })

    for (name, entryA) in aMap {
        if let entryB = bMap[name] {
            if entriesEqual(entryA, entryB) {
                result.same.addEntry(entryA)
            } else {
                result.modified.addEntry(entryB)
            }
        } else {
            result.removed.addEntry(entryA)
        }
    }

    for (name, entryB) in bMap {
        if aMap[name] == nil {
            result.added.addEntry(entryB)
        }
    }

    result.added.sortEntries()
    result.removed.sortEntries()
    result.modified.sortEntries()
    result.same.sortEntries()

    return result
}

/// Combine multiple manifests, keeping the latest version of each path.
public func union(_ manifests: Manifest...) -> Manifest {
    var seen: [String: Entry] = [:]
    for m in manifests {
        for entry in m.entries {
            seen[entry.name] = entry
        }
    }
    var result = Manifest()
    for entry in seen.values {
        result.addEntry(entry)
    }
    result.sortEntries()
    return result
}

/// Return only entries whose paths exist in all manifests.
public func intersect(_ manifests: Manifest...) -> Manifest {
    guard let first = manifests.first else { return Manifest() }

    var common: [String: Entry] = Dictionary(first.entries.map { ($0.name, $0) }, uniquingKeysWith: { _, b in b })

    for m in manifests.dropFirst() {
        let current = Set(m.entries.map(\.name))
        for key in common.keys where !current.contains(key) {
            common.removeValue(forKey: key)
        }
    }

    var result = Manifest()
    for entry in common.values { result.addEntry(entry) }
    result.sortEntries()
    return result
}

/// Remove entries in `remove` from `from`.
public func subtract(_ remove: Manifest, from base: Manifest) -> Manifest {
    let removeSet = Set(remove.entries.map(\.name))
    var result = Manifest()
    for entry in base.entries {
        if !removeSet.contains(entry.name) {
            result.addEntry(entry)
        }
    }
    result.sortEntries()
    return result
}

// MARK: - Internal

private func entriesEqual(_ a: Entry, _ b: Entry) -> Bool {
    guard a.name == b.name else { return false }

    if !a.c4id.isNil && !b.c4id.isNil {
        return a.c4id == b.c4id && a.mode == b.mode
    }

    return a.mode == b.mode &&
           a.size == b.size &&
           a.timestamp == b.timestamp &&
           a.target == b.target
}
