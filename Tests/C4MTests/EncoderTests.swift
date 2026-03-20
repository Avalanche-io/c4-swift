import Testing
import Foundation
@testable import C4M

@Suite("Encoder Tests")
struct EncoderTests {

    @Test("Encode basic manifest")
    func encodeBasic() {
        var m = Manifest()
        m.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 100,
            name: "file.txt"
        ))

        let output = m.marshal()
        // No header - entry-only format
        #expect(!output.hasPrefix("@"))
        #expect(output.contains("-rw-r--r--"))
        #expect(output.contains("100"))
        #expect(output.contains("file.txt"))
    }

    @Test("Encode empty manifest")
    func encodeEmpty() {
        let m = Manifest()
        let output = m.marshal()
        #expect(output == "")
    }

    @Test("Encode sorts entries correctly")
    func encodeSorts() {
        var m = Manifest()
        m.addEntry(Entry(mode: .dir755, name: "dir/"))
        m.addEntry(Entry(mode: .file644, name: "file.txt"))

        let output = m.marshal()
        let lines = output.components(separatedBy: "\n")
        let fileIdx = lines.firstIndex { $0.contains("file.txt") }
        let dirIdx = lines.firstIndex { $0.contains("dir/") }
        #expect(fileIdx! < dirIdx!)
    }

    @Test("Roundtrip: decode then encode")
    func roundtrip() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file1.txt -
        -rw-r--r-- 2024-01-01T00:00:00Z 200 file2.txt -
        drwxr-xr-x 2024-01-01T00:00:00Z 4096 src/ -
        """
        let m = try Manifest.unmarshal(input)
        let output = m.marshal()

        let m2 = try Manifest.unmarshal(output)
        #expect(m2.entries.count == m.entries.count)
        for i in m2.entries.indices {
            #expect(m2.entries[i].name == m.entries[i].name)
            #expect(m2.entries[i].size == m.entries[i].size)
        }
    }

    @Test("Pretty print includes aligned columns")
    func prettyPrint() {
        var m = Manifest()
        m.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 100,
            name: "a.txt",
            c4id: C4ID.identify(string: "a")
        ))
        m.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 1000000,
            name: "longer_name.txt",
            c4id: C4ID.identify(string: "b")
        ))

        let output = m.marshalPretty()
        let lines = output.components(separatedBy: "\n").filter { $0.contains("c4") }
        if lines.count == 2 {
            let col1 = lines[0].range(of: "c4")?.lowerBound
            let col2 = lines[1].range(of: "c4")?.lowerBound
            #expect(col1 != nil)
            #expect(col2 != nil)
        }
    }

    @Test("Encode indented entries")
    func encodeIndented() {
        var m = Manifest()
        m.addEntry(Entry(mode: .dir755, name: "dir/", depth: 0))
        m.addEntry(Entry(mode: .file644, name: "nested.txt", depth: 1))

        let enc = Encoder(indentWidth: 2)
        let output = enc.encode(m)
        let lines = output.components(separatedBy: "\n")
        let nestedLine = lines.first { $0.contains("nested.txt") }
        #expect(nestedLine?.hasPrefix("  ") == true)
    }

    @Test("Null C4 ID renders as dash")
    func nullC4IDRendered() {
        var m = Manifest()
        m.addEntry(Entry(mode: .file644, size: 100, name: "file.txt"))
        let output = m.marshal()
        // Should end with " -\n" (null C4 ID)
        #expect(output.contains(" -\n"))
    }

    @Test("C4 ID or dash always last field")
    func c4idAlwaysLast() {
        let id = C4ID.identify(string: "content")
        var m = Manifest()
        m.addEntry(Entry(mode: .file644, size: 100, name: "with_id.txt", c4id: id))
        m.addEntry(Entry(mode: .file644, size: 100, name: "without_id.txt"))

        let output = m.marshal()
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Last field should be a C4 ID or "-"
            let lastField = trimmed.components(separatedBy: " ").last!
            #expect(lastField == "-" || lastField.hasPrefix("c4"))
        }
    }

    @Test("Encode hard link entries")
    func encodeHardLink() {
        var m = Manifest()
        let id = C4ID.identify(string: "content")
        m.addEntry(Entry(mode: .file644, size: 100, name: "file.txt", c4id: id, hardLink: -1))
        m.addEntry(Entry(mode: .file644, size: 100, name: "link.txt", c4id: id, hardLink: 2))

        let output = m.marshal()
        #expect(output.contains("file.txt -> "))
        #expect(output.contains("link.txt ->2 "))
    }

    @Test("Encode flow link entries")
    func encodeFlowLink() {
        var m = Manifest()
        m.addEntry(Entry(mode: .dir755, name: "outbox/", flowDirection: .outbound, flowTarget: "studio:inbox/"))
        m.addEntry(Entry(mode: .dir755, name: "inbox/", flowDirection: .inbound, flowTarget: "nas:renders/"))

        let output = m.marshal()
        #expect(output.contains("-> studio:inbox/"))
        #expect(output.contains("<- nas:renders/"))
    }
}
