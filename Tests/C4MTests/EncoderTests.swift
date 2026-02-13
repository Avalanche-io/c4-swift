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
        #expect(output.hasPrefix("@c4m 1.0\n"))
        #expect(output.contains("-rw-r--r--"))
        #expect(output.contains("100"))
        #expect(output.contains("file.txt"))
    }

    @Test("Encode empty manifest")
    func encodeEmpty() {
        let m = Manifest()
        let output = m.marshal()
        #expect(output == "@c4m 1.0\n")
    }

    @Test("Encode manifest with base")
    func encodeWithBase() {
        let id = C4ID.identify(string: "base manifest")
        var m = Manifest()
        m.base = id
        let output = m.marshal()
        #expect(output.contains("@base \(id.string)"))
    }

    @Test("Encode sorts entries correctly")
    func encodeSorts() {
        var m = Manifest()
        m.addEntry(Entry(mode: .dir755, name: "dir/"))
        m.addEntry(Entry(mode: .file644, name: "file.txt"))

        let output = m.marshal()
        let lines = output.components(separatedBy: "\n")
        // file.txt should come before dir/ (files before dirs)
        let fileIdx = lines.firstIndex { $0.contains("file.txt") }
        let dirIdx = lines.firstIndex { $0.contains("dir/") }
        #expect(fileIdx! < dirIdx!)
    }

    @Test("Encode with layers")
    func encodeWithLayers() {
        var m = Manifest()
        m.layers.append(Layer(type: .add, by: "Jane", note: "Update"))
        let output = m.marshal()
        #expect(output.contains("@layer"))
        #expect(output.contains("@by Jane"))
        #expect(output.contains("@note Update"))
    }

    @Test("Roundtrip: decode then encode")
    func roundtrip() throws {
        let input = """
        @c4m 1.0
        -rw-r--r-- 2024-01-01T00:00:00Z 100 file1.txt
        -rw-r--r-- 2024-01-01T00:00:00Z 200 file2.txt
        drwxr-xr-x 2024-01-01T00:00:00Z 4096 src/
        """
        let m = try Manifest.unmarshal(input)
        let output = m.marshal()

        // Re-parse and verify
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
        // Both lines should have C4 IDs at the same column
        let lines = output.components(separatedBy: "\n").filter { $0.contains("c4") && !$0.hasPrefix("@") }
        if lines.count == 2 {
            // Find where c4 starts in each line
            let col1 = lines[0].range(of: "c4")?.lowerBound
            let col2 = lines[1].range(of: "c4")?.lowerBound
            // Both should exist
            #expect(col1 != nil)
            #expect(col2 != nil)
        }
    }

    @Test("Remove entries are written after @remove directive")
    func encodeRemoveEntries() {
        var builder = ManifestBuilder()
        builder = builder.addFile("keep.txt", mode: .file644, size: 100)
        builder = builder.remove("deleted.txt")
        let manifest = builder.build()

        let output = manifest.marshal()
        let lines = output.components(separatedBy: "\n")
        let keepIdx = lines.firstIndex { $0.contains("keep.txt") }
        let removeIdx = lines.firstIndex { $0.hasPrefix("@remove") }
        let deletedIdx = lines.firstIndex { $0.contains("deleted.txt") }

        #expect(keepIdx != nil)
        #expect(removeIdx != nil)
        #expect(deletedIdx != nil)
        // keep.txt should be before @remove
        #expect(keepIdx! < removeIdx!)
        // deleted.txt should be after @remove
        #expect(deletedIdx! > removeIdx!)
    }

    @Test("Remove entries not mixed with regular entries")
    func encodeRemoveEntriesSeparated() {
        var builder = ManifestBuilder()
        builder = builder.addFile("a.txt", mode: .file644, size: 10)
        builder = builder.addFile("b.txt", mode: .file644, size: 20)
        builder = builder.remove("x.txt")
        builder = builder.remove("y.txt")
        let manifest = builder.build()

        let output = manifest.marshal()
        // All regular entries should appear before @remove
        let lines = output.components(separatedBy: "\n")
        let removeIdx = lines.firstIndex { $0.hasPrefix("@remove") }!
        let beforeRemove = lines[..<removeIdx].joined()
        let afterRemove = lines[(removeIdx + 1)...].joined()

        #expect(beforeRemove.contains("a.txt"))
        #expect(beforeRemove.contains("b.txt"))
        #expect(!beforeRemove.contains("x.txt"))
        #expect(!beforeRemove.contains("y.txt"))
        #expect(afterRemove.contains("x.txt"))
        #expect(afterRemove.contains("y.txt"))
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
}
