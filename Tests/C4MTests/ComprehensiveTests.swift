import Testing
import Foundation
@testable import C4M

@Suite("Comprehensive Tests")
struct ComprehensiveTests {

    // MARK: - merge()

    @Test("merge: clean merge with non-overlapping changes")
    func mergeClean() {
        let ts = Date(timeIntervalSince1970: 1704067200)
        var base = Manifest()
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 100, name: "shared.txt", c4id: C4ID.identify(string: "shared")))

        var local = base
        local.addEntry(Entry(mode: .file644, timestamp: ts, size: 200, name: "local_new.txt", c4id: C4ID.identify(string: "local")))

        var remote = base
        remote.addEntry(Entry(mode: .file644, timestamp: ts, size: 300, name: "remote_new.txt", c4id: C4ID.identify(string: "remote")))

        let result = merge(base: base, local: local, remote: remote)
        #expect(result.conflicts.isEmpty)
        let names = Set(result.merged.entries.map(\.name))
        #expect(names.contains("shared.txt"))
        #expect(names.contains("local_new.txt"))
        #expect(names.contains("remote_new.txt"))
    }

    @Test("merge: conflict detection when both sides modify same file")
    func mergeConflict() {
        let ts = Date(timeIntervalSince1970: 1704067200)
        let baseID = C4ID.identify(string: "original")
        var base = Manifest()
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 100, name: "file.txt", c4id: baseID))

        let localID = C4ID.identify(string: "local change")
        var local = Manifest()
        local.addEntry(Entry(mode: .file644, timestamp: ts, size: 110, name: "file.txt", c4id: localID))

        let remoteID = C4ID.identify(string: "remote change")
        var remote = Manifest()
        remote.addEntry(Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: 1704067300), size: 120, name: "file.txt", c4id: remoteID))

        let result = merge(base: base, local: local, remote: remote)
        #expect(result.conflicts.count == 1)
        #expect(result.conflicts[0].path == "file.txt")
    }

    @Test("merge: both deleted is not a conflict")
    func mergeBothDeleted() {
        let ts = Date(timeIntervalSince1970: 1704067200)
        var base = Manifest()
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 100, name: "file.txt", c4id: C4ID.identify(string: "content")))
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 200, name: "keep.txt", c4id: C4ID.identify(string: "keep")))

        // Both local and remote remove file.txt but keep keep.txt
        var local = Manifest()
        local.addEntry(Entry(mode: .file644, timestamp: ts, size: 200, name: "keep.txt", c4id: C4ID.identify(string: "keep")))

        var remote = Manifest()
        remote.addEntry(Entry(mode: .file644, timestamp: ts, size: 200, name: "keep.txt", c4id: C4ID.identify(string: "keep")))

        let result = merge(base: base, local: local, remote: remote)
        #expect(result.conflicts.isEmpty)
        let names = result.merged.entries.map(\.name)
        #expect(!names.contains("file.txt"))
        #expect(names.contains("keep.txt"))
    }

    // MARK: - applyPatch()

    @Test("applyPatch: addition")
    func patchAddition() {
        let ts = Date(timeIntervalSince1970: 1704067200)
        var base = Manifest()
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 100, name: "existing.txt"))

        var patch = Manifest()
        patch.addEntry(Entry(mode: .file644, timestamp: ts, size: 200, name: "new.txt"))

        let result = applyPatch(base: base, patch: patch)
        let names = result.entries.map(\.name)
        #expect(names.contains("existing.txt"))
        #expect(names.contains("new.txt"))
    }

    @Test("applyPatch: modification")
    func patchModification() {
        let ts = Date(timeIntervalSince1970: 1704067200)
        var base = Manifest()
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 100, name: "file.txt", c4id: C4ID.identify(string: "old")))

        var patch = Manifest()
        patch.addEntry(Entry(mode: .file644, timestamp: ts, size: 200, name: "file.txt", c4id: C4ID.identify(string: "new")))

        let result = applyPatch(base: base, patch: patch)
        #expect(result.entries.count == 1)
        #expect(result.entries[0].size == 200)
    }

    @Test("applyPatch: removal (identical entry in patch)")
    func patchRemoval() {
        let ts = Date(timeIntervalSince1970: 1704067200)
        let id = C4ID.identify(string: "content")
        var base = Manifest()
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 100, name: "file.txt", c4id: id))
        base.addEntry(Entry(mode: .file644, timestamp: ts, size: 200, name: "keep.txt"))

        // Patch with identical entry = removal
        var patch = Manifest()
        patch.addEntry(Entry(mode: .file644, timestamp: ts, size: 100, name: "file.txt", c4id: id))

        let result = applyPatch(base: base, patch: patch)
        let names = result.entries.map(\.name)
        #expect(!names.contains("file.txt"))
        #expect(names.contains("keep.txt"))
    }

    // MARK: - computeC4ID()

    @Test("computeC4ID: matches known_ids.json manifest vector")
    func computeC4IDMatchesVector() throws {
        let url = Bundle.module.url(forResource: "known_ids", withExtension: "json", subdirectory: "Vectors")!
        let data = try Data(contentsOf: url)

        struct Vectors: Decodable {
            let manifest_vectors: [MV]
            struct MV: Decodable {
                let canonical: String
                let manifest_c4id: String
            }
        }

        let vectors = try JSONDecoder().decode(Vectors.self, from: data)
        let v = vectors.manifest_vectors[0]
        let manifest = try Manifest.unmarshal(v.canonical)
        let id = manifest.computeC4ID()
        #expect(id.string == v.manifest_c4id)
    }

    // MARK: - safeName() / unsafeName()

    @Test("safeName: tier 1 passthrough")
    func safeNameTier1() {
        #expect(safeName("hello.txt") == "hello.txt")
        #expect(safeName("file-name_v2.tar.gz") == "file-name_v2.tar.gz")
    }

    @Test("safeName: tier 2 escapes")
    func safeNameTier2() {
        #expect(safeName("a\tb") == "a\\tb")
        #expect(safeName("a\nb") == "a\\nb")
        #expect(safeName("a\rb") == "a\\rb")
        #expect(safeName("a\\b") == "a\\\\b")
        #expect(safeName("a\0b") == "a\\0b")
    }

    @Test("safeName: tier 3 braille")
    func safeNameTier3() {
        // Byte 0x01 (SOH) is not a tier 2 character, should use braille
        let input = String(UnicodeScalar(1)!)
        let encoded = safeName(input)
        #expect(encoded.contains("\u{00A4}"))
        // Round-trip
        #expect(unsafeName(encoded) == input)
    }

    @Test("safeName/unsafeName: round-trip")
    func safeNameRoundTrip() {
        let testCases = [
            "simple.txt",
            "has space.txt",
            "tab\there",
            "newline\nhere",
            "null\0byte",
            "backslash\\path",
        ]
        for tc in testCases {
            let encoded = safeName(tc)
            let decoded = unsafeName(encoded)
            #expect(decoded == tc, "Round-trip failed for input: \(tc.debugDescription)")
        }
    }

    // MARK: - validate()

    @Test("validate: valid manifest passes")
    func validateValid() throws {
        var m = Manifest()
        m.addEntry(Entry(mode: .file644, size: 100, name: "file.txt"))
        m.addEntry(Entry(mode: .dir755, size: 0, name: "dir/"))
        try m.validate()
    }

    @Test("validate: empty name throws")
    func validateEmptyName() {
        var m = Manifest()
        m.addEntry(Entry(mode: .file644, size: 100, name: ""))
        #expect(throws: C4MError.self) {
            try m.validate()
        }
    }

    @Test("validate: path traversal throws")
    func validatePathTraversal() {
        var m = Manifest()
        m.addEntry(Entry(mode: .file644, size: 100, name: ".."))
        #expect(throws: C4MError.self) {
            try m.validate()
        }
    }

    @Test("validate: duplicate paths throws")
    func validateDuplicatePaths() {
        var m = Manifest()
        m.addEntry(Entry(mode: .file644, size: 100, name: "file.txt"))
        m.addEntry(Entry(mode: .file644, size: 200, name: "file.txt"))
        #expect(throws: C4MError.self) {
            try m.validate()
        }
    }

    // MARK: - Tree Navigation

    @Test("children(of:) returns direct children")
    func childrenOf() throws {
        let input = "drwxr-xr-x 2024-01-01T00:00:00Z 0 src/ -\n  -rw-r--r-- 2024-01-01T00:00:00Z 100 main.swift -\n  -rw-r--r-- 2024-01-01T00:00:00Z 200 utils.swift -"
        let m = try Manifest.unmarshal(input)
        let dir = m.entries.first { $0.name == "src/" }!
        let kids = m.children(of: dir)
        #expect(kids.count == 2)
        let kidNames = Set(kids.map(\.name))
        #expect(kidNames.contains("main.swift"))
        #expect(kidNames.contains("utils.swift"))
    }

    @Test("parent(of:) returns parent directory")
    func parentOf() throws {
        let input = "drwxr-xr-x 2024-01-01T00:00:00Z 0 src/ -\n  -rw-r--r-- 2024-01-01T00:00:00Z 100 main.swift -"
        let m = try Manifest.unmarshal(input)
        let file = m.entries.first { $0.name == "main.swift" }!
        let p = m.parent(of: file)
        #expect(p != nil)
        #expect(p!.name == "src/")
    }

    @Test("parent(of:) returns nil for root entry")
    func parentOfRoot() throws {
        let input = "-rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt -"
        let m = try Manifest.unmarshal(input)
        let p = m.parent(of: m.entries[0])
        #expect(p == nil)
    }

    @Test("siblings(of:) returns sibling entries")
    func siblingsOf() throws {
        let input = "drwxr-xr-x 2024-01-01T00:00:00Z 0 src/ -\n  -rw-r--r-- 2024-01-01T00:00:00Z 100 a.swift -\n  -rw-r--r-- 2024-01-01T00:00:00Z 200 b.swift -\n  -rw-r--r-- 2024-01-01T00:00:00Z 300 c.swift -"
        let m = try Manifest.unmarshal(input)
        let b = m.entries.first { $0.name == "b.swift" }!
        let sibs = m.siblings(of: b)
        #expect(sibs.count == 2)
        let sibNames = Set(sibs.map(\.name))
        #expect(sibNames.contains("a.swift"))
        #expect(sibNames.contains("c.swift"))
    }

    @Test("ancestors(of:) returns parent chain")
    func ancestorsOf() throws {
        let input = "drwxr-xr-x 2024-01-01T00:00:00Z 0 a/ -\n  drwxr-xr-x 2024-01-01T00:00:00Z 0 b/ -\n    -rw-r--r-- 2024-01-01T00:00:00Z 100 deep.txt -"
        let m = try Manifest.unmarshal(input)
        let deep = m.entries.first { $0.name == "deep.txt" }!
        let anc = m.ancestors(of: deep)
        #expect(anc.count == 2)
        #expect(anc[0].name == "b/")
        #expect(anc[1].name == "a/")
    }

    @Test("entryPath() returns full path")
    func entryPathTest() throws {
        let input = "drwxr-xr-x 2024-01-01T00:00:00Z 0 src/ -\n  -rw-r--r-- 2024-01-01T00:00:00Z 100 main.swift -"
        let m = try Manifest.unmarshal(input)
        let file = m.entries.first { $0.name == "main.swift" }!
        let path = m.entryPath(file)
        #expect(path == "src/main.swift")
    }

    // MARK: - canonicalize()

    @Test("canonicalize: nil-infectious size propagation")
    func canonicalizeNilInfectiousSize() {
        var m = Manifest()
        m.addEntry(Entry(mode: .dir755, timestamp: Entry.nullTimestamp, size: -1, name: "dir/", depth: 0))
        m.addEntry(Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: 1704067200), size: 100, name: "a.txt", depth: 1))
        m.addEntry(Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: 1704067200), size: -1, name: "b.txt", depth: 1))

        m.canonicalize()

        let dir = m.entries.first { $0.name == "dir/" }!
        // Null child size should make parent size null (nil-infectious)
        #expect(dir.size == -1)
    }

    @Test("canonicalize: null child timestamp propagates to parent")
    func canonicalizeNilInfectiousTimestamp() {
        var m = Manifest()
        m.addEntry(Entry(mode: .dir755, timestamp: Entry.nullTimestamp, size: -1, name: "dir/", depth: 0))
        m.addEntry(Entry(mode: .file644, timestamp: Entry.nullTimestamp, size: 100, name: "a.txt", depth: 1))
        m.addEntry(Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: 1704067200), size: 200, name: "b.txt", depth: 1))

        m.canonicalize()

        let dir = m.entries.first { $0.name == "dir/" }!
        // Null child timestamp should make parent timestamp null
        #expect(dir.timestamp == Entry.nullTimestamp)
    }

    @Test("canonicalize: all children have values, parent inherits sum and max time")
    func canonicalizePropagation() {
        let ts1 = Date(timeIntervalSince1970: 1704067200)
        let ts2 = Date(timeIntervalSince1970: 1704067300)

        var m = Manifest()
        m.addEntry(Entry(mode: .dir755, timestamp: Entry.nullTimestamp, size: -1, name: "dir/", depth: 0))
        m.addEntry(Entry(mode: .file644, timestamp: ts1, size: 100, name: "a.txt", depth: 1))
        m.addEntry(Entry(mode: .file644, timestamp: ts2, size: 200, name: "b.txt", depth: 1))

        m.canonicalize()

        let dir = m.entries.first { $0.name == "dir/" }!
        #expect(dir.size == 300)
        #expect(dir.timestamp == ts2)
    }
}
