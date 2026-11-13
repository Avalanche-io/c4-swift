import Testing
import Foundation
@testable import C4M

/// A description that names an external base keeps it through encode and
/// decode. Through 2026-11-13 the encoder dropped `base`, so decoding then
/// encoding turned a block on a base into a standalone description of the
/// block's own entries (c4 core fixed the same fault in its encoder, c4 #145).
@Suite("Encode keeps an external base")
struct EncodeBaseTests {

    static let base = C4ID.identify(string: "prior block")

    /// One entry line built through the library, never typed by hand.
    static var entryLine: String {
        let e = Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1_767_225_600), // 2026-01-01T00:00:00Z
            size: 1,
            name: "a.txt",
            c4id: C4ID.identify(string: "a")
        )
        return e.canonical + "\n"
    }

    @Test("Decode then encode writes the base first and changes nothing else")
    func encodeKeepsBase() throws {
        let text = Self.base.string + "\n" + Self.entryLine

        let m = try Manifest.unmarshal(text)
        #expect(m.base == Self.base, "decode keeps the base")

        let out = try m.marshal()
        #expect(out == text, "encode must write the base first and change nothing else")

        let back = try Manifest.unmarshal(out)
        #expect(back.base == Self.base, "round trip keeps the base")
        #expect(back.entries.count == 1)
        #expect(back.entries.first?.name == "a.txt")
    }

    @Test("Pretty encoding starts with the base line")
    func prettyKeepsBase() throws {
        let m = try Manifest.unmarshal(Self.base.string + "\n" + Self.entryLine)
        #expect(try m.marshalPretty().hasPrefix(Self.base.string + "\n"))
    }

    @Test("A manifest with no base encodes with no bare line")
    func noBaseNoBareLine() throws {
        var m = try Manifest.unmarshal(Self.base.string + "\n" + Self.entryLine)
        m.base = nil
        #expect(try m.marshal() == Self.entryLine)
    }

    @Test("A base alone encodes as the base line and decodes back")
    func baseOnly() throws {
        let m = Manifest(base: Self.base)
        let out = try m.marshal()
        #expect(out == Self.base.string + "\n")
        #expect(try Manifest.unmarshal(out).base == Self.base)
    }
}
