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

// MARK: - Three-Way Merge

/// A conflict from a three-way merge.
public struct MergeConflict: Sendable {
    /// Full path of the conflicting entry.
    public var path: String
    /// Entry in the base manifest (nil if added).
    public var baseEntry: Entry?
    /// Entry in the local manifest (nil if deleted).
    public var localEntry: Entry?
    /// Entry in the remote manifest (nil if deleted).
    public var remoteEntry: Entry?
}

/// Result of a three-way merge.
public struct MergeResult: Sendable {
    /// The merged manifest.
    public var merged: Manifest
    /// Conflicts that could not be auto-resolved.
    public var conflicts: [MergeConflict]
}

/// Perform a three-way merge of manifests.
/// base is the common ancestor. local and remote are the diverged states.
public func merge(base: Manifest, local: Manifest, remote: Manifest) -> MergeResult {
    let baseMap = entryPaths(base.entries)
    let localMap = entryPaths(local.entries)
    let remoteMap = entryPaths(remote.entries)

    // Collect all unique paths
    var allPaths = Set<String>()
    for p in baseMap.keys { allPaths.insert(p) }
    for p in localMap.keys { allPaths.insert(p) }
    for p in remoteMap.keys { allPaths.insert(p) }

    var merged: [String: Entry] = [:]
    var conflicts: [MergeConflict] = []

    for p in allPaths.sorted() {
        let b = baseMap[p]
        let l = localMap[p]
        let r = remoteMap[p]

        if b == nil && l != nil && r == nil {
            merged[p] = l!
        } else if b == nil && l == nil && r != nil {
            merged[p] = r!
        } else if b == nil && l != nil && r != nil {
            if mergeEqual(l!, r!) {
                merged[p] = l!
            } else {
                conflicts.append(MergeConflict(path: p, baseEntry: nil, localEntry: l, remoteEntry: r))
                // Keep newer
                if r!.timestamp > l!.timestamp {
                    merged[p] = r!
                } else {
                    merged[p] = l!
                }
            }
        } else if b != nil && l != nil && r != nil {
            let lChanged = !mergeEqual(b!, l!)
            let rChanged = !mergeEqual(b!, r!)
            if !lChanged && !rChanged {
                merged[p] = b!
            } else if lChanged && !rChanged {
                merged[p] = l!
            } else if !lChanged && rChanged {
                merged[p] = r!
            } else {
                if mergeEqual(l!, r!) {
                    merged[p] = l!
                } else {
                    conflicts.append(MergeConflict(path: p, baseEntry: b, localEntry: l, remoteEntry: r))
                    if r!.timestamp > l!.timestamp {
                        merged[p] = r!
                    } else {
                        merged[p] = l!
                    }
                }
            }
        } else if b != nil && l != nil && r == nil {
            if mergeEqual(b!, l!) {
                // Unchanged locally, remote deleted -> delete
            } else {
                conflicts.append(MergeConflict(path: p, baseEntry: b, localEntry: l, remoteEntry: nil))
                merged[p] = l!
            }
        } else if b != nil && l == nil && r != nil {
            if mergeEqual(b!, r!) {
                // Unchanged remotely, local deleted -> delete
            } else {
                conflicts.append(MergeConflict(path: p, baseEntry: b, localEntry: nil, remoteEntry: r))
                merged[p] = r!
            }
        }
        // Both deleted: agreement, omit from result
    }

    // Rebuild manifest from paths
    var result = Manifest()
    for p in merged.keys.sorted() {
        var entry = merged[p]!
        entry.name = pathEntryName(p)
        entry.depth = pathToDepth(p)
        result.addEntry(entry)
    }
    result.sortEntries()

    return MergeResult(merged: result, conflicts: conflicts)
}

// MARK: - Patch Application

/// Apply a patch to a base manifest.
/// Patch semantics: identical entry = removal, new entry = addition, different = modification.
public func applyPatch(base: Manifest, patch: Manifest) -> Manifest {
    let baseMap = entryPaths(base.entries)
    var resultMap = baseMap

    let patchMap = entryPaths(patch.entries)

    for (path, patchEntry) in patchMap {
        if let baseEntry = resultMap[path] {
            if entriesIdentical(baseEntry, patchEntry) {
                // Exact duplicate = removal
                resultMap.removeValue(forKey: path)
            } else {
                // Modification = replace
                resultMap[path] = patchEntry
            }
        } else {
            // Addition
            resultMap[path] = patchEntry
        }
    }

    var result = Manifest()
    // Merge range data
    for (k, v) in base.rangeData { result.rangeData[k] = v }
    for (k, v) in patch.rangeData { result.rangeData[k] = v }

    for p in resultMap.keys.sorted() {
        var entry = resultMap[p]!
        entry.name = pathEntryName(p)
        entry.depth = pathToDepth(p)
        result.addEntry(entry)
    }
    result.sortEntries()
    return result
}

// MARK: - Internal Helpers

private func entriesEqual(_ a: Entry, _ b: Entry) -> Bool {
    guard a.name == b.name else { return false }

    if let aID = a.c4id, let bID = b.c4id, !aID.isNil && !bID.isNil {
        return aID == bID && a.mode == b.mode
    }

    return a.mode == b.mode &&
           a.size == b.size &&
           a.timestamp == b.timestamp &&
           a.target == b.target
}

private func entriesIdentical(_ a: Entry, _ b: Entry) -> Bool {
    a.name == b.name &&
    a.mode == b.mode &&
    a.size == b.size &&
    a.timestamp == b.timestamp &&
    a.target == b.target &&
    a.c4id == b.c4id &&
    a.hardLink == b.hardLink &&
    a.flowDirection == b.flowDirection &&
    a.flowTarget == b.flowTarget
}

private func mergeEqual(_ a: Entry, _ b: Entry) -> Bool {
    if a.isDir != b.isDir { return false }
    if a.isDir {
        return a.flowDirection == b.flowDirection && a.flowTarget == b.flowTarget
    }
    if a.isSymlink || b.isSymlink {
        return a.isSymlink == b.isSymlink && a.target == b.target
    }
    return a.c4id == b.c4id
}

/// Build full paths from flat entry list.
func entryPaths(_ entries: [Entry]) -> [String: Entry] {
    var result: [String: Entry] = [:]
    var stack: [String] = []

    for e in entries {
        while stack.count > e.depth {
            stack.removeLast()
        }

        var fullPath = stack.joined() + e.name
        result[fullPath] = e

        if e.isDir {
            stack.append(e.name)
        }
    }

    return result
}

/// Return the last component of a full path.
private func pathEntryName(_ fullPath: String) -> String {
    let isDir = fullPath.hasSuffix("/")
    let clean = isDir ? String(fullPath.dropLast()) : fullPath
    if let idx = clean.lastIndex(of: "/") {
        let name = String(clean[clean.index(after: idx)...])
        return isDir ? name + "/" : name
    }
    return isDir ? clean + "/" : fullPath
}

/// Return the depth of an entry given its full path.
private func pathToDepth(_ fullPath: String) -> Int {
    let clean = fullPath.hasSuffix("/") ? String(fullPath.dropLast()) : fullPath
    return clean.filter { $0 == "/" }.count
}
