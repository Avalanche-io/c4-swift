import Testing
import Foundation
@testable import C4M

/// Cross-implementation vector: a range's size counts its ID list (c4 #161).
/// SequenceSizeVector/ is a byte-identical copy of the Go reference repo's
/// c4m/testdata/sequence-size-vector/ at c4 master b82ec07 (see its
/// README.md).
///
/// Ruled 2026-11-13 by the maintainer: "The size is the size of every frame
/// and the frame id list." A range's size is its frames' sizes plus count ×
/// 90 (the bare concatenation of member C4 IDs), null if any frame's size is
/// null. A directory holding a range is sized, and identified, from its
/// folded listing. This port has no normaliser that restates a directory's
/// stated size or ID, and no scanner: the directory half is checked by
/// deriving `sub/`'s size and ID from its folded children with the
/// library, which is what a conforming normaliser writes.
@Suite("Sequence Size Vector Conformance")
struct SequenceSizeVectorTests {

    private static func text(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "c4m", subdirectory: "SequenceSizeVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The manifest of the direct children of the directory at index i.
    private static func listing(_ m: Manifest, _ i: Int) -> Manifest {
        var out = Manifest()
        for c in m.children(of: m.entries[i]) { out.addEntry(c) }
        return out
    }

    /// Re-derive sub/'s size and C4 ID from its folded children, as a
    /// conforming normaliser does.
    private static func derive(_ m: Manifest) throws -> Manifest {
        var m = m
        let i = try #require(m.entries.firstIndex { $0.name == "sub/" })
        let listing = listing(m, i)
        m.entries[i].size = -1
        m.entries[i].c4id = listing.computeC4ID()
        m.canonicalize()
        return m
    }

    @Test("folding frames.c4m gives the range 303: 33 bytes of frames and a 3 × 90-byte ID list")
    func rangeSize() throws {
        let folded = detectSequences(in: try Manifest.unmarshal(try Self.text("frames")), minLength: 3)
        let r = try #require(folded.entries.first { $0.isSequence })
        #expect(r.name == "f.[001-003].exr")
        #expect(r.size == 33 + 3 * 90 && !r.sizeIsNull, "range size \(r.size)")
        #expect(folded.rangeData[r.c4id!].map { $0.utf8.count } == 3 * 90)
    }

    @Test("folding frames.c4m and deriving sub/ from its folded listing writes folded.c4m byte for byte")
    func foldWritesFolded() throws {
        let folded = try Self.derive(detectSequences(in: try Manifest.unmarshal(try Self.text("frames")), minLength: 3))
        #expect(try folded.marshal() == (try Self.text("folded")))
        let sub = try #require(folded.entries.first { $0.name == "sub/" })
        #expect(sub.size == 303 + 143, "sub/ size \(sub.size): the range plus its 143-byte folded listing")
    }

    @Test("folded.c4m states what its folded listing derives: deriving changes nothing")
    func foldedIsDerived() throws {
        let m = try Manifest.unmarshal(try Self.text("folded"))
        #expect(try Self.derive(m).marshal() == (try Self.text("folded")))
    }

    @Test("expanded.c4m: the range keeps 303 and each frame's size is null")
    func expandedSizes() throws {
        let m = try Manifest.unmarshal(try Self.text("expanded"))
        let r = try #require(m.entries.first { $0.isSequence })
        #expect(r.size == 303)
        let frames = m.entries.filter { !$0.isSequence && $0.name.hasSuffix(".exr") }
        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.sizeIsNull })
    }

    @Test("a null frame size makes the range's size null, and sub/'s")
    func nullFrame() throws {
        var frames = try Manifest.unmarshal(try Self.text("frames"))
        let i = try #require(frames.entries.firstIndex { $0.name == "f.002.exr" })
        frames.entries[i].size = -1
        let folded = try Self.derive(detectSequences(in: frames, minLength: 3))
        for e in folded.entries where e.isSequence || e.name == "sub/" {
            #expect(e.sizeIsNull, "\(e.name): size \(e.size), want null")
        }
    }

    @Test("a fold shares nothing with its input: editing the fold leaves the input's bytes as they were (c4 #162)")
    func foldSharesNothing() throws {
        let frames = try Manifest.unmarshal(try Self.text("frames"))
        let before = try frames.marshal()
        var folded = try Self.derive(detectSequences(in: frames, minLength: 3))
        for i in folded.entries.indices { folded.entries[i].timestamp += 3600 }
        #expect(try frames.marshal() == before)
    }
}
