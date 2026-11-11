import Testing
import Foundation
@testable import C4M

/// Cross-implementation name-rule vector (c4 core, c4m/testdata/
/// name-rule-vector; the fixtures under NameRuleVector/ are byte-identical
/// copies). A name is a bare entry name, never a path: only "/" separates
/// paths in c4m, and a name may end in "/" only as a directory's marker;
/// ".", "..", "./", "../" and "/" are path components. Through 1.0.26
/// c4m-swift refused the names holding a "/" only by accident (what followed
/// the cut failed as a C4 ID field), read the path components as names, and
/// wrote all of them raw.
@Suite("Name Rule Vector Conformance")
struct NameRuleVectorTests {
    static let cases: [String: String] = [
        "file-sub": "sub/real.txt",
        "file-leading-slash": "/real.txt",
        "file-trailing-path": "real.txt/x",
        "file-dotdot-inside": "a/../real.txt",
        "file-dot": ".",
        "file-dotdot": "..",
        "dir-nested": "a/empty/",
        "dir-dot": "./",
        "dir-dotdot": "../",
        "dir-root": "/",
        "dir-double-slash": "empty//",
    ]
    static let ts = Date(timeIntervalSince1970: 1767323045)

    private static func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "c4m", subdirectory: "NameRuleVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("both ok lines decode")
    func okLinesDecode() throws {
        for ok in ["ok-file", "ok-dir"] {
            #expect(try Manifest.unmarshal(try Self.fixture(ok)).entries.count == 1)
        }
    }

    @Test("every damaged name is refused by the name rule, naming line 1")
    func refusesEachCase() throws {
        for file in Self.cases.keys.sorted() {
            do {
                _ = try Manifest.unmarshal(try Self.fixture(file))
                Issue.record("\(file) decoded instead of being refused")
            } catch let C4MError.invalidEntry(line, msg) {
                #expect(line == 1, "\(file)")
                #expect(msg.contains("is a path"), "\(file): \(msg)")
            }
        }
    }

    @Test("a forbidden name has no C4 ID and no canonical text, flat or nested")
    func forbiddenNameHasNoC4ID() {
        let hello = C4ID.identify(string: "hello\n")
        var flat = Manifest()
        flat.addEntry(Entry(mode: FileMode(rawValue: 0o644), timestamp: Self.ts, size: 6, name: "sub/real.txt", c4id: hello))
        var nested = Manifest()
        nested.addEntry(Entry(mode: FileMode(rawValue: 0x4000 | 0o755), timestamp: Self.ts, size: -1, name: "d/"))
        nested.addEntry(Entry(mode: FileMode(rawValue: 0o644), timestamp: Self.ts, size: 6, name: "../real.txt", c4id: hello, depth: 1))
        for m in [flat, nested] {
            #expect(m.computeC4ID().isNil)
            #expect(m.canonical() == "")
        }
        var ok = Manifest()
        ok.addEntry(Entry(mode: FileMode(rawValue: 0o644), timestamp: Self.ts, size: 6, name: "real.txt", c4id: hello))
        #expect(!ok.computeC4ID().isNil)
    }

    @Test("a backslash is a literal name character, as in Go")
    func backslashIsLiteral() {
        #expect(!isPathName("a\\b.txt"))
        #expect(isPathName("a/b.txt"))
    }

    /// The encoder half is held: `Encoder.encode` returns `String` and cannot
    /// refuse without becoming `throws`, a breaking change to a published
    /// API, which is a release decision put to Joshua (2026-11-11). Until it
    /// is decided the encoder writes these names raw, as through 1.0.26.
    @Test("the encoder refuses a forbidden name", .disabled("held: Encoder.encode() throws is a breaking API change, awaiting Joshua's decision"))
    func encoderRefuses() {
        for name in Self.cases.values {
            var m = Manifest()
            m.addEntry(Entry(mode: FileMode(rawValue: 0o644), timestamp: Self.ts, size: 1, name: name))
            #expect(!Encoder().encode(m).contains(" \(name) "), "\(name) was written")
        }
    }
}
