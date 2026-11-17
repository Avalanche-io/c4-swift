import Testing
import Foundation
@testable import C4M

/// Cross-implementation vector: a time inside the epoch second (c4 #192).
/// EpochSecondVector/ is a byte-identical copy of the Go reference repo's
/// c4m/testdata/epoch-second-vector/ (see its README.md).
///
/// A c4m line carries the second a time falls in, and the epoch is null,
/// so a time that floors to the epoch second is null and its line is "-".
/// c4m-swift has no scanner; an entry a caller built with such a time was
/// written 1970-01-01T00:00:00Z, which reads back as null, so the
/// manifest's C4 ID differed from the ID of its own text.
@Suite("Epoch-second Vector Conformance")
struct EpochSecondVectorTests {

    private static func text(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "EpochSecondVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// One entry built in memory at t seconds after the epoch: whether it is
    /// null, how its line spells the time, and whether the manifest's ID is
    /// its own text's.
    private static func built(_ t: TimeInterval) throws -> (null: Bool, field: String, converges: Bool) {
        let e = Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: t), size: 1, name: "f.txt")
        var m = Manifest()
        m.addEntry(e)
        let text = try Encoder().encode(m)
        let again = try Manifest.unmarshal(text)
        return (Entry.timestampIsNull(e.timestamp), String(text.split(separator: " ")[1]), m.computeC4ID() == again.computeC4ID())
    }

    @Test("a built entry is null exactly when its time floors to the epoch second", arguments: [
        (0.0, true), (0.000_001, true), (0.5, true), (0.999, true),
        (1.0, false), (-0.000_001, false), (-0.5, false), (1_750_000_000.0, false),
    ])
    func builtEntry(t: TimeInterval, null: Bool) throws {
        let r = try Self.built(t)
        #expect(r.null == null)
        #expect((r.field == "-") == null, "written \(r.field)")
        #expect(r.converges)
    }

    @Test("every time in tree.txt: null iff it floors to the epoch second, and the ID converges")
    func treeTimes() throws {
        for line in try Self.text("tree", "txt").split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            let ns = Int64(parts[1])!
            let t = Double(ns) / 1e9
            let r = try Self.built(t)
            let wantNull = ns >= 0 && ns < 1_000_000_000
            #expect(r.null == wantNull, "\(parts[2])")
            #expect(r.converges, "\(parts[2])")
        }
    }

    @Test("saved.c4m resolves to root-id.txt and re-encodes to itself")
    func saved() throws {
        let saved = try Self.text("saved", "c4m")
        let m = try Manifest.unmarshal(saved)
        #expect(m.computeC4ID().string == (try Self.text("root-id", "txt")).trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(try Encoder().encode(m) == saved)
    }
}
