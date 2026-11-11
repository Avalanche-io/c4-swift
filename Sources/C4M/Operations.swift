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

    // Keyed by full path, as bytes: never by bare name (same-named entries
    // in different folders are different entries) and never by String
    // (whose equality makes the NFC and NFD spellings one name). Through
    // 1.0.25 this keyed by bare name, so a change to a/x.txt beside b/x.txt
    // was reported as "x.txt same".
    let aMap = entryPaths(lhs.entries)
    let bMap = entryPaths(rhs.entries)

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
/// Paths are full paths compared as bytes, as in diff.
public func union(_ manifests: Manifest...) -> Manifest {
    var seen: [ByteKey: Entry] = [:]
    for m in manifests {
        for (path, entry) in entryPaths(m.entries) {
            seen[path] = entry
        }
    }
    return manifestFromPaths(seen)
}

/// Return only entries whose paths exist in all manifests.
/// Paths are full paths compared as bytes, as in diff.
public func intersect(_ manifests: Manifest...) -> Manifest {
    guard let first = manifests.first else { return Manifest() }

    var common = entryPaths(first.entries)
    for m in manifests.dropFirst() {
        let current = entryPaths(m.entries)
        for key in common.keys where current[key] == nil {
            common.removeValue(forKey: key)
        }
    }
    return manifestFromPaths(common)
}

/// Remove entries in `remove` from `from`.
/// Paths are full paths compared as bytes, as in diff.
public func subtract(_ remove: Manifest, from base: Manifest) -> Manifest {
    let removePaths = entryPaths(remove.entries)
    var kept = entryPaths(base.entries)
    for key in removePaths.keys {
        kept.removeValue(forKey: key)
    }
    return manifestFromPaths(kept)
}

/// A manifest of the entries at these full paths, each named and placed by
/// its path.
private func manifestFromPaths(_ paths: [ByteKey: Entry]) -> Manifest {
    var result = Manifest()
    for p in paths.keys.sorted() {
        var entry = paths[p]!
        entry.name = pathEntryName(p.string)
        entry.depth = pathToDepth(p.string)
        result.addEntry(entry)
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
    var allPaths = Set<ByteKey>()
    for p in baseMap.keys { allPaths.insert(p) }
    for p in localMap.keys { allPaths.insert(p) }
    for p in remoteMap.keys { allPaths.insert(p) }

    var merged: [ByteKey: Entry] = [:]
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
                conflicts.append(MergeConflict(path: p.string, baseEntry: nil, localEntry: l, remoteEntry: r))
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
                    conflicts.append(MergeConflict(path: p.string, baseEntry: b, localEntry: l, remoteEntry: r))
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
                conflicts.append(MergeConflict(path: p.string, baseEntry: b, localEntry: l, remoteEntry: nil))
                merged[p] = l!
            }
        } else if b != nil && l == nil && r != nil {
            if mergeEqual(b!, r!) {
                // Unchanged remotely, local deleted -> delete
            } else {
                conflicts.append(MergeConflict(path: p.string, baseEntry: b, localEntry: nil, remoteEntry: r))
                merged[p] = r!
            }
        }
        // Both deleted: agreement, omit from result
    }

    // Rebuild manifest from paths
    return MergeResult(merged: manifestFromPaths(merged), conflicts: conflicts)
}

// MARK: - Patch Application

/// Apply a patch to a base manifest.
/// Patch semantics: new entry = addition; different = modification; an
/// identical restatement with no children under it = removal of the entry
/// and everything beneath it; an identical directory restated with children
/// under it = deepening (the directory is unchanged and the children are
/// merged). Erratum 2026-07-31, SPECIFICATION.md "Patch Entry Semantics":
/// a section that declares children is not removing their parent.
/// Breadth-first discovery learns a directory's children before anything
/// about the directory itself, so its line is necessarily restated
/// unchanged. To remove a subtree, restate the directory alone.
public func applyPatch(base: Manifest, patch: Manifest) -> Manifest {
    let baseMap = entryPaths(base.entries)
    var resultMap = baseMap

    let patchMap = entryPaths(patch.entries)

    // Directories the patch lists children under. Computed up front so the
    // outcome does not depend on dictionary iteration order.
    var deepened = Set<ByteKey>()
    for path in patchMap.keys {
        var parent = path.isDirPath ? Array(path.bytes.dropLast()) : path.bytes
        while let idx = parent.lastIndex(of: 0x2F) {
            parent = Array(parent[..<idx])
            deepened.insert(ByteKey(bytes: parent + [0x2F]))
        }
    }

    for (path, patchEntry) in patchMap {
        guard let baseEntry = resultMap[path] else {
            // Addition
            resultMap[path] = patchEntry
            continue
        }
        if !entriesIdentical(baseEntry, patchEntry) {
            // Modification = replace
            resultMap[path] = patchEntry
            continue
        }
        if patchEntry.isDir && deepened.contains(path) {
            // Deepening: the directory stays, its children are merged
            continue
        }
        // Exact duplicate = removal, with everything beneath it
        resultMap.removeValue(forKey: path)
        if path.isDirPath {
            for key in resultMap.keys where key.hasPrefix(path) {
                resultMap.removeValue(forKey: key)
            }
        }
    }

    var result = Manifest()
    // Merge range data
    for (k, v) in base.rangeData { result.rangeData[k] = v }
    for (k, v) in patch.rangeData { result.rangeData[k] = v }

    for p in resultMap.keys.sorted() {
        var entry = resultMap[p]!
        entry.name = pathEntryName(p.string)
        entry.depth = pathToDepth(p.string)
        result.addEntry(entry)
    }
    result.sortEntries()
    return result
}

// MARK: - Internal Helpers

private func entriesEqual(_ a: Entry, _ b: Entry) -> Bool {
    guard sameBytes(a.name, b.name) else { return false }

    if let aID = a.c4id, let bID = b.c4id, !aID.isNil && !bID.isNil {
        return aID == bID && a.mode == b.mode
    }

    return a.mode == b.mode &&
           a.size == b.size &&
           a.timestamp == b.timestamp &&
           sameBytes(a.target, b.target)
}

private func entriesIdentical(_ a: Entry, _ b: Entry) -> Bool {
    sameBytes(a.name, b.name) &&
    a.mode == b.mode &&
    a.size == b.size &&
    a.timestamp == b.timestamp &&
    sameBytes(a.target, b.target) &&
    a.c4id == b.c4id &&
    a.hardLink == b.hardLink &&
    a.flowDirection == b.flowDirection &&
    sameBytes(a.flowTarget, b.flowTarget)
}

private func mergeEqual(_ a: Entry, _ b: Entry) -> Bool {
    if a.isDir != b.isDir { return false }
    if a.isDir {
        return a.flowDirection == b.flowDirection && sameBytes(a.flowTarget, b.flowTarget)
    }
    if a.isSymlink || b.isSymlink {
        return a.isSymlink == b.isSymlink && sameBytes(a.target, b.target)
    }
    return a.c4id == b.c4id
}

/// Build full paths from flat entry list.
private func entryPaths(_ entries: [Entry]) -> [ByteKey: Entry] {
    var result: [ByteKey: Entry] = [:]
    var stack: [String] = []

    for e in entries {
        while stack.count > e.depth {
            stack.removeLast()
        }

        let fullPath = stack.joined() + e.name
        result[ByteKey(fullPath)] = e

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
