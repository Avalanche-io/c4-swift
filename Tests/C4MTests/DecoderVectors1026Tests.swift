import Testing
import Foundation
@testable import C4M

/// Cross-implementation conformance for the 1.0.26 decoder rules. The files
/// under BackslashNameVector/ and DamagedLineVector/ are byte-identical copies
/// of the Go reference repo's c4m/testdata/backslash-name-vector and
/// damaged-line-vector; each README states what every implementation MUST do.
/// (The link-target vector has its own test, LinkTargetVectorTests.)
///
/// - A backslash always starts a two-byte escape, so a name or link target
///   ending in a backslash reads back as itself.
/// - A damaged field is an error naming the line, never a value: a size
///   token ends at a space; each mode position holds only its own letter or
///   "-"; a C4 ID field that does not parse is refused.
struct DecoderVectors1026Tests {
    private static func fixture(_ dir: String, _ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: dir)!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let backslash: [String: String] = [
        "plain.txt": "",
        "trail\\": "",
        "end\\\\": "",
        "a\\ b": "",
        "link": "target\\",
        "dir\\x/": "",
        "in.txt": "",
    ]

    @Test("backslash-name vector: every name and target reads back as itself", arguments: ["canonical", "pretty", "patch"])
    func backslashNames(form: String) throws {
        let m = try Manifest.unmarshal(try Self.fixture("BackslashNameVector", form, "c4m"))
        var got: [String: String] = [:]
        for e in m.entries { got[e.name] = e.target }
        #expect(got == Self.backslash, "\(form)")
        if form != "patch" {
            let root = try Self.fixture("BackslashNameVector", "root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(m.computeC4ID().string == root, "\(form): root ID")
        }
    }

    @Test("damaged-line vector: ok.c4m decodes")
    func damagedOK() throws {
        _ = try Manifest.unmarshal(try Self.fixture("DamagedLineVector", "ok", "c4m"))
    }

    @Test("damaged-line vector: every damaged file is refused, naming line 1", arguments: [
        "id-89", "id-91", "id-bad-char", "size-junk", "size-null-junk",
        "mode-bad-char", "mode-wrong-letter", "mode-sticky-letter-misplaced", "time-impossible",
    ])
    func damagedRefused(name: String) throws {
        let text = try Self.fixture("DamagedLineVector", name, "c4m")
        do {
            _ = try Manifest.unmarshal(text)
            Issue.record("\(name) decoded instead of being refused")
        } catch let C4MError.invalidEntry(line, _) {
            #expect(line == 1, "\(name)")
        }
    }
}
