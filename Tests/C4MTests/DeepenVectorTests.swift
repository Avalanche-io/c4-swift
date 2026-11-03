import Testing
import Foundation
@testable import C4M

/// Cross-implementation deepen-vs-remove vector (erratum, 2026-07-31). The
/// fixtures under DeepenVector/ are byte-identical copies of the Go reference
/// repo's c4m/testdata/deepen-vector/ (see its README.md). Both files restate
/// the same directory line byte-identically; they differ only in whether a
/// child follows it, and must resolve to different manifests.
///
/// Conformance is on the resolved entry set, not only on the ID: a reader
/// carrying the old rule returns the wrong manifest, and one that drops a
/// directory but keeps its children can still compute the right root ID.
@Suite("Deepen Vector Conformance")
struct DeepenVectorTests {

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "DeepenVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func resolve(_ name: String) throws -> (names: [String], id: String) {
        let manifest = try Manifest.unmarshal(try fixture(name, "c4m"))
        return (manifest.entries.map { $0.name }.sorted(), manifest.computeC4ID().string)
    }

    @Test("deepen.c4m: a directory restated with a child is deepened, not removed")
    func deepenResolves() throws {
        let expected = try Self.fixture("deepen-root-id", "txt")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let got = try Self.resolve("deepen")
        #expect(got.names == ["a.txt", "docs/", "guide.md", "readme.md"])
        #expect(got.id == expected)
    }

    @Test("remove.c4m: a directory restated alone is removed with its children")
    func removeResolves() throws {
        let expected = try Self.fixture("remove-root-id", "txt")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let got = try Self.resolve("remove")
        #expect(got.names == ["a.txt"])
        #expect(got.id == expected)
    }

    @Test("the same restated line means opposite things depending on what follows it")
    func deepenAndRemoveDiffer() throws {
        #expect(try Self.resolve("deepen").id != Self.resolve("remove").id)
    }
}
