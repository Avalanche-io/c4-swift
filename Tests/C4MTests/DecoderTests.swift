import Testing
import Foundation
@testable import C4M

@Suite("Decoder Tests")
struct DecoderTests {

    @Test("Parse basic entry")
    func parseBasic() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries.count == 1)
        #expect(m.entries[0].name == "file.txt")
        #expect(m.entries[0].size == 100)
        #expect(m.entries[0].mode == FileMode(string: "-rw-r--r--"))
    }

    @Test("Parse empty input")
    func parseEmpty() throws {
        let m = try Manifest.unmarshal("")
        #expect(m.entries.isEmpty)
    }

    @Test("Parse multiple entries")
    func parseMultiple() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file1.txt -
        -rw-r--r-- 2024-01-01T00:00:00Z 200 file2.txt -
        drwxr-xr-x 2024-01-01T00:00:00Z 0 dir/ -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries.count == 3)
    }

    @Test("Parse directory entry")
    func parseDirectory() throws {
        let input = """
        drwxr-xr-x 2024-01-01T00:00:00Z 4096 src/ -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].isDir)
        #expect(m.entries[0].name == "src/")
    }

    @Test("Parse symlink entry")
    func parseSymlink() throws {
        let input = """
        lrwxrwxrwx 2024-01-01T00:00:00Z 0 link -> target -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].isSymlink)
        #expect(m.entries[0].name == "link")
        #expect(m.entries[0].target == "target")
    }

    @Test("Parse symlink to absolute path")
    func parseSymlinkAbsolute() throws {
        let input = """
        lrwxrwxrwx 2024-01-01T00:00:00Z 0 link -> /absolute/path/target -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].target == "/absolute/path/target")
    }

    @Test("Parse backslash-escaped filename with spaces")
    func parseEscapedFilename() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 2048 my\\ file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].name == "my file.txt")
    }

    @Test("Parse indented entry")
    func parseIndented() throws {
        let input = "drwxr-xr-x 2024-01-01T00:00:00Z 0 dir/ -\n  -rw-r--r-- 2024-01-01T00:00:00Z 512 nested.txt -"
        let m = try Manifest.unmarshal(input)
        #expect(m.entries.count == 2)
        #expect(m.entries[1].depth == 1)
        #expect(m.entries[1].name == "nested.txt")
    }

    @Test("Bare C4 ID on first line sets base")
    func parseBase() throws {
        let id = C4ID.identify(string: "base manifest")
        let input = """
        \(id.string)
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.base != nil)
        #expect(m.base == id)
    }

    @Test("Directive lines rejected")
    func directiveRejected() {
        #expect(throws: C4MError.self) {
            try Manifest.unmarshal("@c4m 1.0\n-rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt -")
        }
    }

    @Test("Parse null mode (single dash)")
    func parseNullMode() throws {
        let input = """
        - 2024-01-01T00:00:00Z 100 file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].mode.isNull)
    }

    @Test("Parse null timestamp (dash)")
    func parseNullTimestamp() throws {
        let input = """
        -rw-r--r-- - 100 file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].timestamp == Entry.nullTimestamp)
    }

    @Test("Parse null size (dash)")
    func parseNullSize() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z - file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].size == -1)
    }

    @Test("Parse entry with C4 ID")
    func parseWithC4ID() throws {
        let id = C4ID.identify(string: "test content")
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt \(id.string)
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].c4id == id)
    }

    @Test("Parse entry with null C4 ID dash")
    func parseNullC4ID() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].c4id == nil)
    }

    @Test("Parse entry with size containing commas")
    func parseSizeWithCommas() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 1,234,567 file.txt -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].size == 1234567)
    }

    @Test("Parse timestamp with timezone offset")
    func parseTimezoneOffset() throws {
        let input = """
        -rw-r--r-- 2024-01-01T10:30:00-07:00 100 file.txt -
        """
        let m = try Manifest.unmarshal(input)
        let expected = Date(timeIntervalSince1970: 1704130200)
        #expect(abs(m.entries[0].timestamp.timeIntervalSince(expected)) < 1)
    }

    @Test("Sequence notation detected")
    func sequenceDetected() throws {
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 10000 frame.[0001-0100].exr -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].isSequence)
        #expect(m.entries[0].pattern == "frame.[0001-0100].exr")
    }

    @Test("Symlink with escaped target containing spaces")
    func symlinkEscapedTarget() throws {
        let input = """
        lrwxrwxrwx 2024-01-01T00:00:00Z 0 link -> target\\ with\\ spaces -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].target == "target with spaces")
    }

    @Test("Parse hard link ungrouped")
    func parseHardLinkUngrouped() throws {
        let id = C4ID.identify(string: "content")
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt -> \(id.string)
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].hardLink == -1)
        #expect(m.entries[0].c4id == id)
    }

    @Test("Parse hard link group")
    func parseHardLinkGroup() throws {
        let id = C4ID.identify(string: "content")
        let input = """
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt ->2 \(id.string)
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].hardLink == 2)
    }

    @Test("Parse flow link outbound")
    func parseFlowOutbound() throws {
        let input = """
        drwxr-xr-x 2024-01-01T00:00:00Z 4096 outbox/ -> studio:inbox/ -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].flowDirection == .outbound)
        #expect(m.entries[0].flowTarget == "studio:inbox/")
    }

    @Test("Parse flow link inbound")
    func parseFlowInbound() throws {
        let input = """
        drwxr-xr-x 2024-01-01T00:00:00Z 4096 inbox/ <- nas:renders/ -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].flowDirection == .inbound)
        #expect(m.entries[0].flowTarget == "nas:renders/")
    }

    @Test("Parse flow link bidirectional")
    func parseFlowBidirectional() throws {
        let input = """
        drwxr-xr-x 2024-01-01T00:00:00Z 4096 shared/ <> peer:shared/ -
        """
        let m = try Manifest.unmarshal(input)
        #expect(m.entries[0].flowDirection == .bidirectional)
        #expect(m.entries[0].flowTarget == "peer:shared/")
    }

    @Test("CR character rejected")
    func crRejected() {
        #expect(throws: C4MError.self) {
            try Manifest.unmarshal("-rw-r--r-- 2024-01-01T00:00:00Z 100 file.txt -\r\n")
        }
    }
}
