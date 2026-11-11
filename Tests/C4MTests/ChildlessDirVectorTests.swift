import Testing
import Foundation
@testable import C4M

/// Cross-implementation conformance: a directory with no listed children and
/// a null size. ChildlessDirVector/ is a byte-identical copy of the Go
/// reference repo's c4m/testdata/childless-dir-vector (README there). What
/// the size derives to depends on the directory's C4 ID alone:
///   empty/      the empty listing's ID  -> 0: known to hold nothing
///   collapsed/  any other ID           -> null: its listing lives elsewhere
///   unread/     no ID                  -> 0 on 1.0.x; null on main
/// Through 1.0.26 a collapsed directory derived to 0, and computeC4ID hashed
/// that invented size. unread/ is a known 1.0.x difference, as on the Go
/// reference's 1.0.27 line, so the committed normalized.c4m and root-id.txt
/// are main's, and this line's own normalised form and ID are checked
/// against themselves and against the 1.0.x ID pinned in every
/// implementation.
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
    private static let want: [String: Int64] = ["empty/": 0, "collapsed/": -1, "unread/": 0]
    private static let lineRootID =
        "c43hjzfaERSHQSgDYwRPabKdXuC1gbHSW1BnXPVhvCm8LNgYj5LEH6a3VoV2gckqiLNMBQEh4dTVKszriwrmZryUkh"

    private static func lineNormalized() throws -> String {
        var m = try Manifest.unmarshal(try text("stated", "c4m"))
        m.canonicalize()
        return m.marshal()
    }

    @Test("sizes derive from the C4 ID alone", arguments: ["stated", "normalized"])
    func sizes(form: String) throws {
        var m = try Manifest.unmarshal(try Self.text(form, "c4m"))
        m.canonicalize()
        var got: [String: Int64] = [:]
        for e in m.entries { got[e.name] = e.size }
        #expect(got == Self.want)
    }

    @Test("main's normalized file differs from this line's only in unread/'s size")
    func mainDiffersOnlyInUnread() throws {
        var m = try Manifest.unmarshal(try Self.text("normalized", "c4m"))
        for i in m.entries.indices where m.entries[i].name == "unread/" {
            m.entries[i].size = 0
        }
        #expect(m.marshal() == (try Self.lineNormalized()))
    }

    @Test("this line's ID is the pinned 1.0.x ID, agrees with itself, and differs from main's")
    func lineID() throws {
        let lineID = try Manifest.unmarshal(try Self.text("stated", "c4m")).computeC4ID().string
        #expect(lineID == Self.lineRootID)
        let normalized = try Self.lineNormalized()
        #expect(try Manifest.unmarshal(normalized).computeC4ID().string == lineID)
        #expect(C4ID.identify(data: Data(normalized.utf8)).string == lineID)
        // If this ever matches, the unread/ difference is gone: update the test.
        #expect(lineID != (try Self.rootID()))
    }

    @Test("the normalized file's own bytes are main's description")
    func bytesAreTheDescription() throws {
        let data = try Data(contentsOf: Self.url("normalized", "c4m"))
        #expect(C4ID.identify(data: data).string == (try Self.rootID()))
    }
}
