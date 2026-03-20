import Testing
import Foundation
@testable import C4M

@Suite("Entry Tests")
struct EntryTests {

    @Test("Entry isDir with trailing slash")
    func isDirTrailingSlash() {
        let e = Entry(name: "src/")
        #expect(e.isDir)
    }

    @Test("Entry isDir with mode")
    func isDirWithMode() {
        let e = Entry(mode: .dir755, name: "src/")
        #expect(e.isDir)
    }

    @Test("Entry is not dir for regular file")
    func isNotDir() {
        let e = Entry(mode: .file644, name: "file.txt")
        #expect(!e.isDir)
    }

    @Test("Entry isSymlink")
    func isSymlink() {
        let e = Entry(mode: .symlink777, name: "link")
        #expect(e.isSymlink)
    }

    @Test("Canonical form has no indentation")
    func canonicalNoIndent() {
        let e = Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 100,
            name: "file.txt",
            depth: 3
        )
        let c = e.canonical
        #expect(!c.hasPrefix(" "))
        #expect(c.contains("-rw-r--r--"))
        #expect(c.contains("100"))
        #expect(c.contains("file.txt"))
    }

    @Test("Canonical null mode renders as single dash")
    func canonicalNullMode() {
        let e = Entry(
            mode: .null,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 100,
            name: "file.txt"
        )
        let c = e.canonical
        // Null mode in canonical form is "-" (single dash)
        #expect(c.hasPrefix("- "))
        #expect(!c.hasPrefix("----------"))
    }

    @Test("Format null mode renders as ten dashes")
    func formatNullMode() {
        let e = Entry(
            mode: .null,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 100,
            name: "file.txt"
        )
        let s = e.format()
        // Display format uses "----------" for null mode
        #expect(s.hasPrefix("----------"))
    }

    @Test("Format with indentation")
    func formatWithIndent() {
        let e = Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 100,
            name: "file.txt",
            depth: 2
        )
        let s = e.format(indentWidth: 2)
        #expect(s.hasPrefix("    "))
    }

    @Test("Null values detection")
    func nullValues() {
        let e = Entry(
            mode: .null,
            timestamp: Entry.nullTimestamp,
            size: -1,
            name: "test.txt"
        )
        #expect(e.hasNullValues)
    }

    @Test("Format name with backslash escaping")
    func formatNameEscaping() {
        #expect(Entry.formatName("simple.txt") == "simple.txt")
        // Spaces are backslash-escaped, not quoted
        #expect(Entry.formatName("has space.txt") == "has\\ space.txt")
        // Quotes are backslash-escaped
        #expect(Entry.formatName("has\"quote.txt") == "has\\\"quote.txt")
        // Directories: escape base part, keep trailing /
        #expect(Entry.formatName("dir/") == "dir/")
        // Brackets are escaped for non-sequence names
        #expect(Entry.formatName("file[1].txt") == "file\\[1\\].txt")
    }

    @Test("Format symlink target with backslash escaping")
    func formatTargetEscaping() {
        #expect(Entry.formatTarget("simple") == "simple")
        #expect(Entry.formatTarget("has space") == "has\\ space")
    }

    @Test("Canonical timestamp format")
    func canonicalTimestamp() {
        let date = Date(timeIntervalSince1970: 1704067200)
        let ts = Entry.canonicalTimestamp(date)
        #expect(ts == "2024-01-01T00:00:00Z")
    }

    @Test("Null timestamp renders as dash")
    func nullTimestamp() {
        let ts = Entry.canonicalTimestamp(Entry.nullTimestamp)
        #expect(ts == "-")
    }

    @Test("Entry with symlink target in canonical form")
    func symlinkCanonical() {
        let e = Entry(
            mode: .symlink777,
            timestamp: Date(timeIntervalSince1970: 1704067200),
            size: 0,
            name: "link.txt",
            target: "target.txt"
        )
        let c = e.canonical
        #expect(c.contains("-> target.txt"))
    }

    @Test("Size with commas formatting")
    func sizeWithCommas() {
        let s = Entry.formatSizeWithCommas(1234567)
        #expect(s == "1,234,567")
    }

    @Test("C4 ID or dash always present in canonical form")
    func c4idOrDashInCanonical() {
        // With C4 ID
        let id = C4ID.identify(string: "content")
        let e1 = Entry(mode: .file644, size: 100, name: "file.txt", c4id: id)
        let c1 = e1.canonical
        #expect(c1.hasSuffix(id.string))

        // Without C4 ID - should end with "-"
        let e2 = Entry(mode: .file644, size: 100, name: "file.txt")
        let c2 = e2.canonical
        #expect(c2.hasSuffix(" -"))
    }

    @Test("Hard link in canonical form")
    func hardLinkCanonical() {
        let id = C4ID.identify(string: "content")
        let e1 = Entry(mode: .file644, size: 100, name: "file.txt", c4id: id, hardLink: -1)
        #expect(e1.canonical.contains("-> " + id.string))

        let e2 = Entry(mode: .file644, size: 100, name: "link.txt", c4id: id, hardLink: 2)
        #expect(e2.canonical.contains("->2 " + id.string))
    }

    @Test("Flow link in canonical form")
    func flowLinkCanonical() {
        let e = Entry(mode: .dir755, name: "outbox/", flowDirection: .outbound, flowTarget: "studio:inbox/")
        #expect(e.canonical.contains("-> studio:inbox/"))

        let e2 = Entry(mode: .dir755, name: "inbox/", flowDirection: .inbound, flowTarget: "nas:renders/")
        #expect(e2.canonical.contains("<- nas:renders/"))
    }
}
