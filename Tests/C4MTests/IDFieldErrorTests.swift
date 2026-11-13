import Testing
import Foundation
@testable import C4M

/// A C4 ID field that does not parse is an error naming the line, never a
/// null. A file torn part way through its last C4 ID (an interrupted write,
/// a truncated download) used to decode with that entry's ID silently null,
/// so a damaged description read as one with an unknown ID: a read error
/// became a value. The text is written by the library and then cut, as a
/// torn write cuts it.
struct IDFieldErrorTests {
    private static func written() throws -> String {
        let id = C4ID.identify(data: Data("some content".utf8))
        let entry = Entry(mode: FileMode(rawValue: 0o644), timestamp: Date(timeIntervalSince1970: 1_767_323_045),
                          size: 12, name: "a.txt", c4id: id)
        let m = Manifest(entries: [entry])
        return try m.marshal()
    }

    @Test("the library's own text decodes")
    func wholeFileDecodes() throws {
        let m = try Manifest.unmarshal(try Self.written())
        #expect(m.entries.first?.c4id != nil)
    }

    @Test("a file torn inside its last C4 ID (89 characters) is refused, naming the line")
    func tornIDIsAnError() throws {
        var text = try Self.written()
        while text.hasSuffix("\n") { text.removeLast() }
        text.removeLast() // the ID field is now 89 characters
        let field = text.split(separator: " ").last.map(String.init) ?? ""
        #expect(field.count == 89)
        do {
            _ = try Manifest.unmarshal(text)
            Issue.record("a torn C4 ID decoded instead of failing")
        } catch let C4MError.invalidEntry(line, message) {
            #expect(line == 1)
            #expect(message.contains("invalid C4 ID"))
        }
    }

    @Test("a C4 ID field one character too long (91) is refused, naming the line")
    func overlongIDIsAnError() throws {
        var text = try Self.written()
        while text.hasSuffix("\n") { text.removeLast() }
        text += "1\n"
        do {
            _ = try Manifest.unmarshal(text)
            Issue.record("an overlong C4 ID decoded instead of failing")
        } catch let C4MError.invalidEntry(line, message) {
            #expect(line == 1)
            #expect(message.contains("invalid C4 ID"))
        }
    }
}
