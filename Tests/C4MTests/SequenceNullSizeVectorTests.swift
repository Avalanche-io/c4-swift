import Testing
import Foundation
@testable import C4M

/// Cross-implementation vector: a folded sequence with a null-size frame
/// (c4 #155; decided 2026-11-13 by the release lead; reversible).
/// SequenceNullSizeVector/ is a byte-identical copy of the Go reference
/// repo's c4m/testdata/sequence-null-size-vector/ at c4 commit 7a6ba94
/// (#156; see its README.md).
///
/// A folded sequence's size is the sum of its frames' sizes, and null if any
/// frame's size is null (`-`, or a 0 beside a C4 ID other than the empty
/// content's): "One cannot use size as an expectation if there are nulls
/// present, so we must say nothing." This port folds sequences
/// (`detectSequences`), so both halves apply: decoding `folded.c4m`, and
/// folding either frames file to it.
@Suite("Sequence Null-size Vector Conformance")
struct SequenceNullSizeVectorTests {

    private static func text(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "SequenceNullSizeVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func rootID() throws -> String {
        try text("folded-root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("folded.c4m decodes to the root ID")
    func decodedRootID() throws {
        let m = try Manifest.unmarshal(try Self.text("folded", "c4m"))
        #expect(m.computeC4ID().string == (try Self.rootID()))
    }

    @Test("the plate range's size is known 24 and the shot range's is null")
    func decodedSizes() throws {
        let m = try Manifest.unmarshal(try Self.text("folded", "c4m"))
        let plate = try #require(m.entries.first { $0.name == "plate.[1001-1004].exr" })
        let shot = try #require(m.entries.first { $0.name == "shot.[1001-1004].exr" })
        #expect(plate.size == 24 && !plate.sizeIsNull)
        #expect(shot.sizeIsNull)
    }

    @Test("folded.c4m re-encodes to itself byte for byte")
    func reencode() throws {
        let m = try Manifest.unmarshal(try Self.text("folded", "c4m"))
        #expect(try m.marshal() == (try Self.text("folded", "c4m")))
    }

    @Test("both frames files fold (minimum length 3) to folded.c4m byte for byte",
          arguments: ["frames", "frames-zero-spelled"])
    func fold(form: String) throws {
        let frames = try Manifest.unmarshal(try Self.text(form, "c4m"))
        let folded = detectSequences(in: frames, minLength: 3)
        let shot = try #require(folded.entries.first { $0.name == "shot.[1001-1004].exr" }, "\(form) did not fold")
        #expect(shot.sizeIsNull, "\(form): shot range size \(shot.size)")
        #expect(try folded.marshal() == (try Self.text("folded", "c4m")))
        #expect(folded.computeC4ID().string == (try Self.rootID()))
    }
}
