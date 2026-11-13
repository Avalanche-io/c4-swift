import Testing
import Foundation
@testable import C4M

/// Cross-implementation vector: a size of 0 beside a C4 ID (c4 #68, ruled
/// 2026-11-08, landed 2026-11-13; decided 2026-11-13 by the release lead;
/// reversible). NullSizeVector/ is a byte-identical copy of the Go
/// reference repo's c4m/testdata/null-size-vector/ (see its README.md).
///
/// Only the empty content has size 0, so a 0 on a file or directory line
/// beside any other C4 ID is a null size: a filesystem surface has no `-`
/// and can only show a null size as 0. A 0 with no C4 ID, a 0 with the
/// empty content's ID, and a symlink's 0 are known zeros.
@Suite("Null-size Vector Conformance")
struct NullSizeVectorTests {

    private static func text(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "NullSizeVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func rootID() throws -> String {
        try text("root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The README's table: nil is a null size, otherwise the known size.
    private static let want: [String: Int64?] = [
        "null.txt": nil,
        "collapsed/": nil,
        "empty.txt": 0,
        "emptydir/": 0,
        "structure.txt": 0,
        "link": 0,
        "known.txt": 5,
    ]

    @Test("both files decode to the root ID", arguments: ["canonical", "zero-spelled"])
    func rootID(form: String) throws {
        let m = try Manifest.unmarshal(try Self.text(form, "c4m"))
        #expect(m.computeC4ID().string == (try Self.rootID()))
    }

    @Test("each entry's size is null or known per the README", arguments: ["canonical", "zero-spelled"])
    func sizes(form: String) throws {
        let m = try Manifest.unmarshal(try Self.text(form, "c4m"))
        #expect(m.entries.count == Self.want.count)
        for (name, size) in Self.want {
            let e = try #require(m.entries.first { $0.name == name }, "\(form): \(name)")
            // The decoder holds a null size as -1, the port's null.
            #expect(e.size == (size ?? -1), "\(form): \(name) size")
        }
    }

    @Test("both files re-encode to canonical.c4m byte for byte", arguments: ["canonical", "zero-spelled"])
    func reencode(form: String) throws {
        let m = try Manifest.unmarshal(try Self.text(form, "c4m"))
        #expect(try m.marshal() == (try Self.text("canonical", "c4m")))
    }
}
