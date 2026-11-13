import Testing
import Foundation
@testable import C4M

/// Cross-implementation name-escape vector (c4 core, c4m/testdata/
/// name-escape-vector; the fixtures under NameEscapeVector/ are
/// byte-identical copies). In a written name a space is "\ ", a double quote
/// is "\"", and a control byte is encoded by SafeName; a raw one is damage and
/// is refused, naming the line. Through 1.0.26 c4m-swift read each into the
/// name ("real.txt junk" became one name). Any consistent indent reads.
@Suite("Name Escape Vector Conformance")
struct NameEscapeVectorTests {
    static let damaged = [
        "file-unescaped-space", "file-damaged-id-field", "file-raw-quote",
        "file-raw-tab", "file-raw-control", "dir-unescaped-space",
    ]

    private static func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "c4m", subdirectory: "NameEscapeVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("every damaged name is refused, naming line 1")
    func refusesEachCase() throws {
        for file in Self.damaged {
            do {
                _ = try Manifest.unmarshal(try Self.fixture(file))
                Issue.record("\(file) decoded instead of being refused")
            } catch let C4MError.invalidEntry(line, _) {
                #expect(line == 1, "\(file)")
            }
        }
    }

    @Test("the ok files decode, the escaped name and the 3-space indent included")
    func okFilesDecode() throws {
        #expect(try Manifest.unmarshal(try Self.fixture("ok-file")).entries.count == 1)
        #expect(try Manifest.unmarshal(try Self.fixture("ok-dir")).entries.count == 1)
        let esc = try Manifest.unmarshal(try Self.fixture("ok-escaped"))
        #expect(esc.entries.map { Array($0.name.utf8) } == [Array("my file \"q\"\t.txt".utf8)])
        let tree = try Manifest.unmarshal(try Self.fixture("ok-indent-3"))
        #expect(tree.entries.map(\.name) == ["d/", "x.txt"])
        #expect(tree.entries.map(\.depth) == [0, 1])
    }

    @Test("a sequence-flagged name with no range is written escaped and reads back")
    func sequenceFallbackEscapes() throws {
        let name = "bad seq \"x\"\u{01}[a]"
        var m = Manifest()
        m.addEntry(Entry(mode: FileMode(rawValue: 0o644), timestamp: Date(timeIntervalSince1970: 1767323045),
                         size: 1, name: name, c4id: C4ID.identify(string: "x"), isSequence: true))
        let text = try Encoder().encode(m)
        #expect(!text.contains("bad seq"))
        #expect(!text.utf8.contains(0x01))
        let back = try Manifest.unmarshal(text)
        #expect(back.entries.map { Array($0.name.utf8) } == [Array(name.utf8)])
    }
}
