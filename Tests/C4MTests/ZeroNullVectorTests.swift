import Testing
import Foundation
@testable import C4M

/// Cross-implementation vector: known zero against null (2026-11-09). The
/// fixtures under ZeroNullVector/ are byte-identical copies of the Go
/// reference repo's c4m/testdata/zero-null-vector/ (see its README.md), and
/// Legacy/ten-dash-null-1.0.21.c4m is a real pretty-form file written by
/// c4 1.0.21, whose encoder wrote every null mode as ten dashes.
///
/// The rule (SPECIFICATION.md "Null and Zero Values", C4M-STANDARD §4.1):
/// `-` is the null mode; `----------` is the known zero mode, a regular file
/// with no permission bits; `d---------` is a known directory at 0000. The
/// one legacy exception: ten dashes on a directory line (name ending in `/`)
/// can only be an old encoder's null, so it decodes as null.
@Suite("Zero-vs-Null Vector Conformance")
struct ZeroNullVectorTests {

    static let emptyContentID =
        "c459dsjfscH38cYeXXYogktxf4Cd9ibshE3BHUo6a58hBXmRQdZrAkZzsWcbWtDg5oQstpDuni4Hirj75GEmTc1sFT"

    private static func fixture(_ name: String, _ ext: String, in dir: String = "ZeroNullVector") throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: dir)!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func rootID() throws -> String {
        try fixture("root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entry(_ m: Manifest, _ name: String) -> Entry? {
        m.entries.first { $0.name == name }
    }

    /// The per-entry expectations every form must decode to.
    private static func checkManifest(_ m: Manifest, form: String) throws {
        #expect(m.entries.count == 7, "\(form): entry count")
        let want = try rootID()
        #expect(m.computeC4ID().string == want, "\(form): root ID")

        let zero = try #require(entry(m, "zero.txt"), "\(form): zero.txt")
        #expect(zero.mode.isZero, "\(form): zero.txt mode is the known zero")
        #expect(!zero.mode.isNull, "\(form): zero.txt mode is not null")
        #expect(zero.mode == .zero)
        #expect(zero.mode.description == "----------")
        #expect(zero.size == 4)
        #expect(zero.c4id != nil)
        #expect(!zero.hasNullValues, "\(form): a known zero is not a null")

        let nullmode = try #require(entry(m, "nullmode.txt"), "\(form): nullmode.txt")
        #expect(nullmode.mode.isNull, "\(form): nullmode.txt mode is null")
        #expect(!nullmode.mode.isZero)
        #expect(nullmode.mode.description == "-")
        #expect(nullmode.size == 4)
        #expect(nullmode.c4id != nil)
        #expect(nullmode.hasNullValues)

        let empty = try #require(entry(m, "empty.txt"), "\(form): empty.txt")
        #expect(empty.mode == .file644)
        #expect(empty.size == 0)
        #expect(empty.c4id?.string == emptyContentID)
        #expect(!empty.hasNullValues)

        let emptydir = try #require(entry(m, "emptydir/"), "\(form): emptydir/")
        #expect(emptydir.mode == .dir755)
        #expect(emptydir.mode.isDir)
        #expect(emptydir.size == 0)
        #expect(emptydir.c4id?.string == emptyContentID)
        #expect(!emptydir.hasNullValues)

        let locked = try #require(entry(m, "locked/"), "\(form): locked/")
        #expect(locked.mode == FileMode(string: "d---------"))
        #expect(locked.mode.isDir)
        #expect(!locked.mode.isNull && !locked.mode.isZero)
        #expect(locked.mode.permissions == 0)
        #expect(locked.mode.description == "d---------")
        #expect(locked.size == 142)
        #expect(locked.c4id != nil)
        #expect(!locked.hasNullValues)

        let inside = try #require(entry(m, "inside.txt"), "\(form): inside.txt")
        #expect(inside.depth == 1)
        #expect(inside.mode == .file644)
        #expect(inside.size == 6)
        #expect(inside.c4id != nil)

        let unread = try #require(entry(m, "unread/"), "\(form): unread/")
        #expect(unread.mode == FileMode(string: "d---------"))
        #expect(unread.mode.isDir)
        #expect(!unread.mode.isNull, "\(form): unread/ mode is known")
        #expect(unread.size == -1, "\(form): unread/ size is null")
        #expect(unread.c4id == nil, "\(form): unread/ ID is null")
        #expect(unread.hasNullValues)
        #expect(m.entries.filter { $0.depth == 1 }.count == 1, "\(form): unread/ has no children")
    }

    @Test("canonical.c4m decodes to the vector's manifest and root ID")
    func canonicalDecodes() throws {
        let m = try Manifest.unmarshal(try Self.fixture("canonical", "c4m"))
        try Self.checkManifest(m, form: "canonical")
    }

    @Test("pretty.c4m decodes to the same manifest and root ID")
    func prettyDecodes() throws {
        let m = try Manifest.unmarshal(try Self.fixture("pretty", "c4m"))
        try Self.checkManifest(m, form: "pretty")
    }

    @Test("both forms decode to one manifest, entry for entry")
    func formsAgree() throws {
        let canonical = try Manifest.unmarshal(try Self.fixture("canonical", "c4m"))
        let pretty = try Manifest.unmarshal(try Self.fixture("pretty", "c4m"))
        #expect(canonical.entries == pretty.entries)
        #expect(canonical.computeC4ID() == pretty.computeC4ID())
    }

    @Test("re-encoding the canonical form reproduces canonical.c4m byte for byte")
    func canonicalRoundTrip() throws {
        let text = try Self.fixture("canonical", "c4m")
        let m = try Manifest.unmarshal(text)
        #expect(m.marshal() == text)
        // And the pretty form, re-encoded canonically, lands on the same bytes.
        let fromPretty = try Manifest.unmarshal(try Self.fixture("pretty", "c4m"))
        #expect(fromPretty.marshal() == text)
    }

    @Test("pretty re-encoding keeps the mode spellings of pretty.c4m line by line")
    func prettyModeSpellings() throws {
        let text = try Self.fixture("pretty", "c4m")
        let m = try Manifest.unmarshal(text)
        let want = text.split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true)[0] }
        let got = m.marshalPretty().split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true)[0] }
        #expect(got == want)
        #expect(want.map(String.init) == ["-rw-r--r--", "-", "----------", "drwxr-xr-x", "d---------", "-rw-r--r--", "d---------"])
    }

    @Test("legacy 1.0.21 file: ten dashes on a directory line decodes as null, on a file line as the known zero")
    func legacyTenDashes() throws {
        let text = try Self.fixture("ten-dash-null-1.0.21", "c4m", in: "Legacy")
        let m = try Manifest.unmarshal(text)
        #expect(m.entries.map { $0.name } == ["a.txt", "d/", "b.txt"])
        for e in m.entries where e.name.hasSuffix("/") {
            #expect(e.mode.isNull, "directory \(e.name) must decode with a null mode")
        }
        for e in m.entries where !e.name.hasSuffix("/") {
            #expect(e.mode.isZero, "file \(e.name) decodes as the known zero (the ruled cost of giving ten dashes a meaning)")
        }
        #expect(m.hasNullValues)
    }

    @Test("legacy file re-encodes null as '-' on every directory line, in both forms")
    func legacyReencode() throws {
        let text = try Self.fixture("ten-dash-null-1.0.21", "c4m", in: "Legacy")
        let m = try Manifest.unmarshal(text)
        for out in [m.marshal(), m.marshalPretty()] {
            for line in out.split(separator: "\n") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                let mode = fields[0]
                let isDir = fields.contains { $0.hasSuffix("/") }
                if isDir {
                    #expect(mode == "-", "directory line must write null as '-': \(line)")
                } else {
                    #expect(mode == "----------", "file line keeps the known zero: \(line)")
                }
            }
        }
    }

    @Test("a ten-dash directory decoded as legacy null round-trips through canonical form as '-'")
    func legacyDirectoryCanonical() throws {
        let m = try Manifest.unmarshal(try Self.fixture("ten-dash-null-1.0.21", "c4m", in: "Legacy"))
        let again = try Manifest.unmarshal(m.marshal())
        #expect(again.entries == m.entries)
        #expect(again.computeC4ID() == m.computeC4ID())
    }

    @Test("an unparseable mode is an error, never a null")
    func invalidModeIsError() {
        #expect(throws: C4MError.self) {
            try Manifest.unmarshal("xrw-r--r-- 2026-01-02T03:04:05Z 4 file.txt -\n")
        }
    }
}
