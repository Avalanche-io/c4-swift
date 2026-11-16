import Testing
import Foundation
@testable import C4M

/// Cross-implementation vector: ID lists through merge, diff and patch
/// (c4 #159, #160). RangeDataVector/ is a byte-identical copy of the Go
/// reference repo's c4m/testdata/range-data-vector/ at c4 master b82ec07
/// (see its README.md).
///
/// Ruled 2026-11-13 by the maintainer: "it is an error to drop the frame IDs
/// in any context." An output carries the ID list of every range it holds
/// and no list for a range it does not; none is invented. This port's
/// operations differ in shape from Go's: merging two c4m files is `union`,
/// or `merge` over an empty base; there is no patch-text writer, so the
/// vector's diff rows are checked as `applyPatch` of the patch files Go
/// wrote, and `diff`'s parts carry their ranges' lists. There is no
/// expander (`Sequence.expand()` gives names, never entries), so no range
/// is ever expanded without its list, and none with a frame given a null
/// C4 ID or the range's own (c4 #160 holds by construction).
@Suite("Range Data Vector Conformance")
struct RangeDataVectorTests {

    private static func text(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "c4m", subdirectory: "RangeDataVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func load(_ name: String) throws -> Manifest {
        try Manifest.unmarshal(try text(name))
    }

    @Test("merging folded.c4m and plain.c4m, either way round, writes merged.c4m with both lists")
    func mergeTwo() throws {
        let folded = try Self.load("folded"), plain = try Self.load("plain")
        let want = try Self.text("merged")
        #expect(try union(folded, plain).marshal() == want)
        #expect(try union(plain, folded).marshal() == want)
        #expect(try merge(base: Manifest(), local: folded, remote: plain).merged.marshal() == want)
        #expect(try merge(base: Manifest(), local: plain, remote: folded).merged.marshal() == want)
        #expect(try Self.load("merged").rangeData.count == 2)
    }

    @Test("merging folded.c4m with itself writes folded.c4m")
    func mergeSelf() throws {
        let folded = try Self.load("folded")
        let want = try Self.text("folded")
        #expect(try union(folded, folded).marshal() == want)
        #expect(try intersect(folded, folded).marshal() == want)
        #expect(try merge(base: folded, local: folded, remote: folded).merged.marshal() == want)
        #expect(try merge(base: Manifest(), local: folded, remote: folded).merged.marshal() == want)
    }

    @Test("patching plain.c4m with add.c4m, and resolving add-chain.c4m, write folded.c4m")
    func patchAdd() throws {
        let want = try Self.text("folded")
        #expect(try applyPatch(base: try Self.load("plain"), patch: try Self.load("add")).marshal() == want)
        #expect(try Self.load("add-chain").marshal() == want)
    }

    @Test("patching folded.c4m with remove.c4m, and resolving remove-chain.c4m, write no-plate.c4m: the plate list goes with its range")
    func patchRemove() throws {
        let want = try Self.text("no-plate")
        #expect(try applyPatch(base: try Self.load("folded"), patch: try Self.load("remove")).marshal() == want)
        #expect(try Self.load("remove-chain").marshal() == want)
        #expect(try Self.load("remove").rangeData.isEmpty, "a removal line takes no list")
    }

    @Test("subtract keeps the list of each range left, and only those")
    func subtractKeeps() throws {
        let folded = try Self.load("folded")
        let left = subtract(try Self.load("no-plate"), from: folded)
        let plate = try #require(left.entries.first { $0.isSequence })
        #expect(left.rangeData.keys.sorted { $0.string < $1.string } == [plate.c4id!])
        #expect(left.rangeData[plate.c4id!] == folded.rangeData[plate.c4id!])
    }

    @Test("diff's parts carry the lists of the ranges they hold")
    func diffParts() throws {
        let folded = try Self.load("folded"), plain = try Self.load("plain"), noPlate = try Self.load("no-plate")
        let add = diff(lhs: plain, rhs: folded)
        #expect(add.added.rangeData == folded.rangeData)
        let rm = diff(lhs: folded, rhs: noPlate)
        let plate = try #require(rm.removed.entries.first { $0.isSequence })
        #expect(Array(rm.removed.rangeData.keys) == [plate.c4id!])
        #expect(rm.same.rangeData == noPlate.rangeData)
    }

    @Test("folding a manifest that already holds ranges keeps their lists")
    func foldKeepsLists() throws {
        let folded = try Self.load("folded")
        #expect(try detectSequences(in: folded, minLength: 3).marshal() == (try Self.text("folded")))
    }

    @Test("folded-no-lists.c4m: each range stays one folded entry, with no frames and no list invented")
    func noListNoExpansion() throws {
        let m = try Self.load("folded-no-lists")
        #expect(m.rangeData.isEmpty)
        #expect(m.entries.filter(\.isSequence).count == 2)
        #expect(m.entries.count == 5)
        #expect(try union(m, m).marshal() == (try Self.text("folded-no-lists")))
    }

    @Test("lists never change a description ID", arguments: ["folded", "merged", "no-plate"])
    func listsDoNotChangeID(name: String) throws {
        let m = try Self.load(name)
        var bare = m
        bare.rangeData = [:]
        #expect(m.computeC4ID() == bare.computeC4ID())
        #expect(try m.marshal() != (try bare.marshal()) || m.rangeData.isEmpty)
    }
}
