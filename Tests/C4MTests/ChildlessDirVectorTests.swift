import Testing
import Foundation
@testable import C4M

/// Cross-implementation conformance: a directory with no listed children and
/// a null size. ChildlessDirVector/ is a byte-identical copy of the Go
/// reference repo's c4m/testdata/childless-dir-vector (README there). What
/// the size derives to depends on the directory's C4 ID alone:
///   empty/      the empty listing's ID  -> 0: known to hold nothing
///   collapsed/  any other ID           -> null: its listing lives elsewhere
///   unread/     no ID                  -> null: nobody listed it
/// Through 2026-11-11 a collapsed directory derived to 0, and computeC4ID
/// hashed that invented size.
struct ChildlessDirVectorTests {
    private static func url(_ name: String, _ ext: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "ChildlessDirVector")!
    }
    private static func text(_ name: String, _ ext: String) throws -> String {
        try String(contentsOf: url(name, ext), encoding: .utf8)
    }
    private static func rootID() throws -> String {
        try text("root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static let want: [String: Int64] = ["empty/": 0, "collapsed/": -1, "unread/": -1]

    @Test("both forms resolve to the root ID", arguments: ["stated", "normalized"])
    func rootID(form: String) throws {
        let m = try Manifest.unmarshal(try Self.text(form, "c4m"))
        #expect(m.computeC4ID().string == (try Self.rootID()))
    }

    @Test("sizes derive from the C4 ID alone", arguments: ["stated", "normalized"])
    func sizes(form: String) throws {
        var m = try Manifest.unmarshal(try Self.text(form, "c4m"))
        m.canonicalize()
        var got: [String: Int64] = [:]
        for e in m.entries { got[e.name] = e.size }
        #expect(got == Self.want)
    }

    @Test("the canonicalized stated form writes the normalized file")
    func writesNormalized() throws {
        var m = try Manifest.unmarshal(try Self.text("stated", "c4m"))
        m.canonicalize()
        #expect(try m.marshal() == (try Self.text("normalized", "c4m")))
    }

    @Test("the normalized file's own bytes are the description")
    func bytesAreTheDescription() throws {
        let data = try Data(contentsOf: Self.url("normalized", "c4m"))
        #expect(C4ID.identify(data: data).string == (try Self.rootID()))
    }
}
