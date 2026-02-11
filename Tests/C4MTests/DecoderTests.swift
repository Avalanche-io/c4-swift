import Testing
import Foundation
@testable import C4M

@Suite("Decoder Tests")
struct DecoderTests {

    @Test("Parse basic manifest")
    func parseBasic() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.version == "1.0")
        #expect(m.entries.count == 1)
        #expect(m.entries[0].name == "file.txt")
        #expect(m.entries[0].size == 100)
        #expect(m.entries[0].mode == FileMode(string: "-rw-r--r--"))
    }

    @Test("Parse empty manifest")
    func parseEmpty() throws {
        let m = try Manifest.unmarshal("@c4m 1.0")
        #expect(m.entries.isEmpty)
    }

    @Test("Parse multiple entries")
    func parseMultiple() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file1.txt
        -rw-r--r-- 2024-01-01T00:00:00Z 200 file2.txt
        drwxr-xr-x 2024-01-01T00:00:00Z 0 dir/
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries.count == 3)
    }

    @Test("Parse directory entry")
    func parseDirectory() throws {
        let input = """
        @c4m 1.0
        drwxr-xr-x 2024-01-01T00:00:00Z 4096 src/
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].isDir)
        #expect(m.entries[0].name == "src/")
    }

    @Test("Parse symlink entry")
    func parseSymlink() throws {
        let input = """
        @c4m 1.0
        lrwxrwxrwx 2024-01-01T00:00:00Z 0 link -> target
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].isSymlink)
        #expect(m.entries[0].name == "link")
        #expect(m.entries[0].target == "target")
    }

    @Test("Parse symlink to absolute path")
    func parseSymlinkAbsolute() throws {
        let input = """
        @c4m 1.0
        lrwxrwxrwx 2024-01-01T00:00:00Z 0 link -> /absolute/path/target
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].target == "/absolute/path/target")
    }

    @Test("Parse quoted filename with spaces")
    func parseQuotedFilename() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z 2048 "my file.txt"
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].name == "my file.txt")
    }

    @Test("Parse indented entry")
    func parseIndented() throws {
        let input = "@c4m 1.0\ndrwxr-xr-x 2024-01-01T00:00:00Z 0 dir/\n  -rw-r--r-- 2024-01-01T00:00:00Z 512 nested.txt"
        let m = try Manifest.unmarshal(input)
        #expect(m.entries.count == 2)
        #expect(m.entries[1].depth == 1)
        #expect(m.entries[1].name == "nested.txt")
    }

    @Test("Parse base directive")
    func parseBase() throws {
        let input = """
        @c4m 1.0
        @base c41HX1X4uedbqHB72FCDXFnifrN1PTWfFZfV2Hh6y3RE9dUy5wJrgzmf9tWnyR9B29AvoJsKNd7RhFbxbumvBtSjtN
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt
        """
        let m = try Manifest.unmarshal(input)
        #expect(!m.base.isNil)
    }

    @Test("Parse layer directives")
    func parseLayers() throws {
        let input = """
        @c4m 1.0
        @layer
        @by Jane Smith
        @note Security update
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.layers.count == 1)
        #expect(m.layers[0].type == .add)
        #expect(m.layers[0].by == "Jane Smith")
        #expect(m.layers[0].note == "Security update")
    }

    @Test("Parse remove directive")
    func parseRemove() throws {
        let input = """
        @c4m 1.0
        @remove
        @by Admin
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.layers.count == 1)
        #expect(m.layers[0].type == .remove)
    }

    @Test("Invalid header rejected")
    func invalidHeader() {
        #expect(throws: C4MError.self) {
            try Manifest.unmarshal("not a c4m file\n-rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt")
        }
    }

    @Test("Unsupported version rejected")
    func unsupportedVersion() {
        #expect(throws: C4MError.self) {
            try Manifest.unmarshal("@c4m 2.0\n-rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt")
        }
    }

    @Test("Empty input rejected")
    func emptyInput() {
        #expect(throws: C4MError.self) {
            try Manifest.unmarshal("")
        }
    }

    @Test("Parse null mode (single dash)")
    func parseNullMode() throws {
        let input = """
        @c4m 1.0
        - 2024-01-01T00:00:00Z 100 file.txt
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].mode.isNull)
    }

    @Test("Parse null timestamp (dash)")
    func parseNullTimestamp() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- - 100 file.txt
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].timestamp == Entry.nullTimestamp)
    }

    @Test("Parse null size (dash)")
    func parseNullSize() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z - file.txt
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].size == -1)
    }

    @Test("Parse entry with C4 ID")
    func parseWithC4ID() throws {
        let id = C4ID.identify(string: "test content")
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt \(id.string)
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].c4id == id)
    }

    @Test("Parse entry with size containing commas")
    func parseSizeWithCommas() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z 1,234,567 file.txt
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].size == 1234567)
    }

    @Test("Parse timestamp with timezone offset")
    func parseTimezoneOffset() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T10:30:00-07:00 100 file.txt
        """
        let m = try Manifest.unmarshal(input)
        // Should be converted to UTC: 17:30:00Z
        let expected = Date(timeIntervalSince1970: 1704130200) // 2024-01-01T17:30:00Z
        #expect(abs(m.entries[0].timestamp.timeIntervalSince(expected)) < 1)
    }

    @Test("Sequence notation detected")
    func sequenceDetected() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z 10000 frame.[0001-0100].exr
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].isSequence)
        #expect(m.entries[0].pattern == "frame.[0001-0100].exr")
    }

    @Test("@end resets current layer")
    func endDirective() throws {
        let input = """
        @c4m 1.0
        @layer
        @by Editor
        @end
        -rw-r--r-- 2024-01-01T00:00:00Z 100 main.txt
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries.count == 1)
        #expect(m.layers.count == 1)
    }

    @Test("Symlink with quoted target containing spaces")
    func symlinkQuotedTarget() throws {
        let input = """
        @c4m 1.0
        lrwxrwxrwx 2024-01-01T00:00:00Z 0 link -> "target with spaces"
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].target == "target with spaces")
    }
}
