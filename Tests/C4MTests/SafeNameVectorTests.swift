import Testing
import Foundation
@testable import C4M

/// Cross-implementation SafeName vector (c4 core, c4m/testdata/
/// safename-vector; the fixtures under SafeNameVector/ are byte-identical
/// copies). Four of its names hold bytes that are not UTF-8, which a Swift
/// String cannot hold exactly. Through 1.0.26 c4m-swift read each as its
/// escaped text, a different name and C4 ID, with no error. They are refused
/// now, naming the line, until it is decided whether c4m-swift carries names
/// as bytes (with Joshua).
@Suite("SafeName Vector Conformance")
struct SafeNameVectorTests {
    static let invalid = ["invalid-ff", "lone-continuation", "overlong-nul", "surrogate"]

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "SafeNameVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func isInvalid(_ line: Substring) -> Bool {
        invalid.contains { line.contains(" \($0)-") }
    }

    @Test("the vector is refused at the line of its first name that is not UTF-8")
    func refusesAtFirstInvalidLine() throws {
        let text = try Self.fixture("names", "c4m")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let first = lines.firstIndex(where: Self.isInvalid)! + 1
        do {
            _ = try Manifest.unmarshal(text)
            Issue.record("decoded instead of being refused")
        } catch let C4MError.invalidEntry(line, _) {
            #expect(line == first)
        }
    }

    @Test("each such line alone is refused at line 1, and every other name reads byte-exact")
    func eachAndTheRest() throws {
        let lines = try Self.fixture("names", "c4m").split(separator: "\n")
        for l in lines where Self.isInvalid(l) {
            do {
                _ = try Manifest.unmarshal(String(l) + "\n")
                Issue.record("\(l) decoded instead of being refused")
            } catch let C4MError.invalidEntry(line, _) {
                #expect(line == 1)
            }
        }
        let rest = lines.filter { !Self.isInvalid($0) }.joined(separator: "\n") + "\n"
        let m = try Manifest.unmarshal(rest)
        let got = Set(m.entries.map { Array($0.name.utf8) })
        for c in try Self.fixture("cases", "txt").split(separator: "\n") {
            let parts = c.split(separator: " ", maxSplits: 2).map(String.init)
            if Self.invalid.contains(parts[0]) { continue }
            var raw: [UInt8] = []
            var i = parts[1].startIndex
            while i < parts[1].endIndex {
                let j = parts[1].index(i, offsetBy: 2)
                raw.append(UInt8(parts[1][i..<j], radix: 16)!)
                i = j
            }
            #expect(got.contains(raw), "\(parts[0])")
        }
    }

    /// Tier 1 is unicode.IsPrint at Unicode 17.0.0, pinned (c4 #149; decided
    /// 2026-11-13 by the release lead; reversible). Through 2026-11-13
    /// c4m-swift wrote 13 of these names raw where Go encodes them.
    @Test("every name Swift can hold is written as Go writes it")
    func writerMatchesGo() throws {
        var checked = 0
        for c in try Self.fixture("cases", "txt").split(separator: "\n") {
            let parts = c.split(separator: " ", maxSplits: 2).map(String.init)
            if Self.invalid.contains(parts[0]) { continue }
            var raw: [UInt8] = []
            var i = parts[1].startIndex
            while i < parts[1].endIndex {
                let j = parts[1].index(i, offsetBy: 2)
                raw.append(UInt8(parts[1][i..<j], radix: 16)!)
                i = j
            }
            let name = try #require(String(bytes: raw, encoding: .utf8), "\(parts[0])")
            #expect(Entry.formatName(name) == parts[2], "\(parts[0])")
            checked += 1
        }
        #expect(checked == 27)
    }
}
