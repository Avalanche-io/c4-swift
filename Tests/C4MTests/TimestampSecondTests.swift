import Testing
import Foundation
@testable import C4M

// A c4m line carries whole seconds (SPECIFICATION.md, "Timestamp"). A Date
// built by a caller can hold a fraction; the encoder writes the second it
// falls in, floored toward negative infinity as Go writes it, and diff and
// applyPatch compare at that second. Every c4m here is built through the
// library, never written by hand.
@Suite("Timestamps at the format's resolution")
struct TimestampSecondTests {

    private func at(_ t: TimeInterval, _ name: String, size: Int64 = 6, c4id: C4ID? = nil) -> Entry {
        Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: t), size: size, name: name, c4id: c4id)
    }

    /// A caller-built tree: fractional times, after and before 1970, with and without C4 IDs.
    private func callerBuilt() -> Manifest {
        var m = Manifest()
        m.addEntry(at(1_750_000_000.5, "no-id.txt"))
        m.addEntry(at(1_750_000_000.5, "with-id.txt", size: 8, c4id: C4ID.identify(string: "with-id\n")))
        m.addEntry(at(1_750_000_000.9999998, "last-ms.txt"))
        m.addEntry(at(-1.5, "pre-half.txt"))
        m.addEntry(at(-1.0000003, "pre-round.txt"))
        m.addEntry(at(1_750_000_000, "whole.txt"))
        m.sortEntries()
        return m
    }

    private func names(_ m: Manifest) -> [String] { m.entries.map(\.name).sorted() }

    @Test("The encoder writes the floored second", arguments: [
        (1_750_000_000.5, "2025-06-15T15:06:40Z"),
        (1_750_000_000.9999998, "2025-06-15T15:06:40Z"),
        (-1.5, "1969-12-31T23:59:58Z"),
        (-1.0000003, "1969-12-31T23:59:58Z"),
        (-1.0, "1969-12-31T23:59:59Z"),
        (-0.5, "1969-12-31T23:59:59Z"),
    ])
    func floored(t: TimeInterval, want: String) {
        #expect(Entry.canonicalTimestamp(Date(timeIntervalSince1970: t)) == want)
    }

    @Test("Pretty form writes the same second, so it resolves to the canonical ID")
    func prettyFloored() throws {
        let m = callerBuilt()
        let pretty = try Manifest.unmarshal(try Encoder(pretty: true).encode(m))
        let canonical = try Manifest.unmarshal(try Encoder().encode(m))
        #expect(pretty.computeC4ID() == canonical.computeC4ID())
    }

    @Test("A caller-built tree diffed against itself loaded from its c4m is empty")
    func diffEmpty() throws {
        let m = callerBuilt()
        let loaded = try Manifest.unmarshal(try Encoder().encode(m))
        let d = diff(lhs: loaded, rhs: m)
        #expect(d.isEmpty, "modified: \(names(d.modified))")
        #expect(names(d.same) == names(m))
    }

    @Test("Applying a patch written from that diff removes nothing")
    func patchKeepsUnchanged() throws {
        let m = callerBuilt()
        let text = try Encoder().encode(m)
        let loaded = try Manifest.unmarshal(text)
        let patch = try Manifest.unmarshal(try Encoder().encode(diff(lhs: loaded, rhs: m).modified))
        #expect(names(applyPatch(base: loaded, patch: patch)) == names(m))
    }

    @Test("Restating an entry's loaded line removes it from the caller-built base")
    func restatementRemoves() throws {
        let m = callerBuilt()
        let loaded = try Manifest.unmarshal(try Encoder().encode(m))
        for name in ["no-id.txt", "last-ms.txt", "pre-round.txt"] {
            var patch = Manifest()
            patch.addEntry(try #require(loaded.entries.first { $0.name == name }))
            #expect(!names(applyPatch(base: m, patch: patch)).contains(name), "\(name)")
        }
    }

    @Test("A change of second is still a modification")
    func secondChange() throws {
        let m = callerBuilt()
        let loaded = try Manifest.unmarshal(try Encoder().encode(m))
        var later = Manifest()
        for e in m.entries {
            later.addEntry(e.name == "no-id.txt" ? at(1_750_000_001.25, "no-id.txt") : e)
        }
        later.sortEntries()
        #expect(names(diff(lhs: loaded, rhs: later).modified) == ["no-id.txt"])
    }
}
