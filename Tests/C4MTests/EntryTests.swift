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
            timestamp: Date(timeIntervalSince1970: 1704067200), // 2024-01-01T00:00:00Z
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
        #expect(s.hasPrefix("    ")) // 2 * 2 = 4 spaces
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

    @Test("Format name with special characters quotes correctly")
    func formatNameQuoting() {
        #expect(Entry.formatName("simple.txt") == "simple.txt")
        #expect(Entry.formatName("has space.txt") == "\"has space.txt\"")
        #expect(Entry.formatName("has\"quote.txt") == "\"has\\\"quote.txt\"")
        #expect(Entry.formatName("dir/") == "dir/") // directories never quoted
    }

    @Test("Format symlink target with special characters")
    func formatTargetQuoting() {
        #expect(Entry.formatTarget("simple") == "simple")
        #expect(Entry.formatTarget("has space") == "\"has space\"")
    }

    @Test("Canonical timestamp format")
    func canonicalTimestamp() {
        let date = Date(timeIntervalSince1970: 1704067200) // 2024-01-01T00:00:00Z
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
}
