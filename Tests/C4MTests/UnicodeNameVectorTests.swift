import Testing
import Foundation
@testable import C4M

/// Cross-implementation unicode-name vector (c4 core, c4m/testdata/
/// unicode-name-vector; the fixtures under UnicodeNameVector/ are
/// byte-identical copies, written by the Go library). Names, a symlink
/// target and a flow-target path that are not ASCII. Through 1.0.25
/// c4m-swift refused every line whose name was not ASCII: its field parsers
/// walked UTF-8 bytes but sliced the line by Character offsets, and its name
/// parser built names one byte per Character.
@Suite("Unicode Name Vector Conformance")
struct UnicodeNameVectorTests {
    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "UnicodeNameVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    static let link = "\u{94fe}\u{63a5}"
    static let flowDir = "\u{53d1}\u{9001}/"

    @Test("both forms decode to exactly the names, targets and root ID", arguments: ["canonical", "pretty"])
    func decodes(_ form: String) throws {
        let m = try Manifest.unmarshal(try Self.fixture(form, "c4m"))
        let want = try Self.fixture("names", "txt").split(separator: "\n").map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: " "))
        }
        // Compare bytes, not Swift's canonically equivalent String equality:
        // the NFC and NFD spellings of café.txt are two names.
        #expect(m.entries.map { Array($0.name.utf8) } == want.map { Array($0.utf8) })
        let rootID = try Self.fixture("root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(m.computeC4ID().string == rootID)
        let link = m.entries.first { Array($0.name.utf8) == Array(Self.link.utf8) }
        #expect(link.map { Array($0.target.utf8) } == Array("\u{76ee}\u{6807}.txt".utf8))
        let flow = m.entries.first { Array($0.name.utf8) == Array(Self.flowDir.utf8) }
        #expect(flow.map { Array($0.flowTarget.utf8) } == Array("nas:\u{30c7}\u{30fc}\u{30bf}/".utf8))
    }

    @Test("decoding then encoding gives back the library's canonical bytes and C4 ID")
    func roundTrips() throws {
        let src = try Self.fixture("canonical", "c4m")
        let m = try Manifest.unmarshal(src)
        let out = Encoder().encode(m)
        #expect(Array(out.utf8) == Array(src.utf8))
        let rootID = try Self.fixture("root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try Manifest.unmarshal(out).computeC4ID().string == rootID)
    }

    @Test("a patch adding the NFD spelling beside the NFC one resolves to both, with Go's ID")
    func nfcNfdChain() throws {
        let m = try Manifest.unmarshal(try Self.fixture("nfc-nfd-chain", "c4m"))
        #expect(m.entries.count == 2)
        #expect(Set(m.entries.map { Array($0.name.utf8) }) == [Array("caf\u{e9}.txt".utf8), Array("cafe\u{301}.txt".utf8)])
        let want = try Self.fixture("nfc-nfd-chain-root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(m.computeC4ID().string == want)
    }
}

/// Set operations key entries by full path, compared as bytes: same-named
/// files in different folders are different entries, and the NFC and NFD
/// spellings of a name are two names. Through 1.0.25 they keyed by bare
/// name as a Swift String, so a change to a/x.txt beside b/x.txt was "same",
/// and a file moved between folders was "same".
@Suite("Set operations key by full path, as bytes")
struct SetOperationPathTests {
    static let ts = Date(timeIntervalSince1970: 1767323045)

    static func tree(_ files: [(dir: String, name: String, content: String)]) -> Manifest {
        var m = Manifest()
        var dirs: [String] = []
        for f in files where !dirs.contains(f.dir) { dirs.append(f.dir) }
        for d in dirs.sorted() {
            if !d.isEmpty {
                m.addEntry(Entry(mode: FileMode(rawValue: 0x4000 | 0o755), timestamp: ts, size: -1, name: d))
            }
            for f in files where f.dir == d {
                m.addEntry(Entry(mode: FileMode(rawValue: 0o644), timestamp: ts, size: Int64(f.content.utf8.count),
                                 name: f.name, c4id: C4ID.identify(string: f.content), depth: d.isEmpty ? 0 : 1))
            }
        }
        m.sortEntries()
        return m
    }

    @Test("diff reports the changed file by its path, and a move as removed and added")
    func diffByPath() {
        let l = Self.tree([("a/", "x.txt", "1"), ("b/", "x.txt", "2")])
        let r = Self.tree([("a/", "x.txt", "9"), ("b/", "x.txt", "2")])
        let d = diff(lhs: l, rhs: r)
        #expect(d.modified.entries.map(\.name).contains("x.txt"))
        #expect(d.same.entries.contains { $0.name == "x.txt" })  // b/x.txt only
        #expect(d.modified.entries.filter { $0.name == "x.txt" }.count == 1)

        let m1 = Self.tree([("a/", "x.txt", "same")])
        let m2 = Self.tree([("b/", "x.txt", "same")])
        let mv = diff(lhs: m1, rhs: m2)
        #expect(mv.removed.entries.map(\.name).contains("x.txt"))
        #expect(mv.added.entries.map(\.name).contains("x.txt"))
        #expect(!mv.same.entries.contains { $0.name == "x.txt" })
    }

    @Test("union, intersect and subtract keep same-named files in different folders apart")
    func setOpsByPath() {
        let a = Self.tree([("a/", "x.txt", "1")])
        let b = Self.tree([("b/", "x.txt", "2")])
        let u = union(a, b)
        #expect(u.entries.filter { $0.name == "x.txt" }.count == 2)
        #expect(intersect(a, b).entries.filter { $0.name == "x.txt" }.isEmpty)
        #expect(subtract(b, from: a).entries.filter { $0.name == "x.txt" }.count == 1)
    }

    @Test("the NFC and NFD spellings of a name are two entries everywhere")
    func nfcNfdAreTwo() {
        let nfc = "caf\u{e9}.txt", nfd = "cafe\u{301}.txt"
        let both = Self.tree([("", nfc, "one"), ("", nfd, "two")])
        #expect(both.entries.count == 2)
        let only = Self.tree([("", nfc, "one")])
        let d = diff(lhs: only, rhs: both)
        #expect(d.added.entries.map { Array($0.name.utf8) } == [Array(nfd.utf8)])
        #expect(union(only, both).entries.count == 2)
        #expect(subtract(only, from: both).entries.map { Array($0.name.utf8) } == [Array(nfd.utf8)])
        #expect(both.getEntry(path: nfd)?.c4id == C4ID.identify(string: "two"))
        #expect(both.getEntry(path: nfc)?.c4id == C4ID.identify(string: "one"))
    }
}
