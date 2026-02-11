import Testing
import Foundation
@testable import C4M

@Suite("Builder Tests")
struct BuilderTests {

    @Test("Build simple manifest with files")
    func buildSimple() {
        let m = ManifestBuilder()
            .addFile("file1.txt", size: 100)
            .addFile("file2.txt", size: 200)
            .build()

        #expect(m.entries.count == 2)
        #expect(m.entries[0].name == "file1.txt")
        #expect(m.entries[1].name == "file2.txt")
    }

    @Test("Build manifest with directory and children")
    func buildWithDirectory() {
        let m = ManifestBuilder()
            .addFile("root.txt")
            .addDir("src/")
                .addFile("main.swift", size: 500)
                .addFile("utils.swift", size: 300)
            .end()
            .build()

        #expect(m.entries.count == 4) // root.txt, src/, main.swift, utils.swift
    }

    @Test("Build manifest with nested directories")
    func buildNested() {
        let m = ManifestBuilder()
            .addDir("src/")
                .addDir("lib/")
                    .addFile("core.swift")
                .endDir()
                .addFile("app.swift")
            .end()
            .build()

        #expect(m.entries.count == 4) // src/, lib/, core.swift, app.swift
        // Check depths
        let srcEntry = m.entries.first { $0.name == "src/" }
        let libEntry = m.entries.first { $0.name == "lib/" }
        let coreEntry = m.entries.first { $0.name == "core.swift" }
        #expect(srcEntry?.depth == 0)
        #expect(libEntry?.depth == 1)
        #expect(coreEntry?.depth == 2)
    }

    @Test("Build manifest with removals")
    func buildWithRemovals() {
        let m = ManifestBuilder()
            .withBaseID(C4ID.identify(string: "base"))
            .remove("old-file.txt")
            .removeDir("deprecated")
            .build()

        #expect(!m.base.isNil)
        #expect(m.layers.count == 1)
        #expect(m.layers[0].type == .remove)
        #expect(m.removals.count == 2)
    }

    @Test("Build manifest with metadata")
    func buildWithMetadata() {
        let m = ManifestBuilder()
            .withBaseID(C4ID.identify(string: "base"))
            .by("Author")
            .note("Test note")
            .remove("file.txt")
            .build()

        #expect(m.layers[0].by == "Author")
        #expect(m.layers[0].note == "Test note")
    }

    @Test("Build manifest with C4 IDs")
    func buildWithC4IDs() {
        let id = C4ID.identify(string: "content")
        let m = ManifestBuilder()
            .addFile("file.txt", size: 100, c4id: id)
            .build()

        #expect(m.entries[0].c4id == id)
    }

    @Test("DirBuilder ensures trailing slash")
    func dirTrailingSlash() {
        let m = ManifestBuilder()
            .addDir("notrailingslash")
                .addFile("child.txt")
            .end()
            .build()

        let dir = m.entries.first { $0.isDir }
        #expect(dir?.name == "notrailingslash/")
    }

    @Test("RemoveDir ensures trailing slash")
    func removeDirTrailingSlash() {
        let m = ManifestBuilder()
            .withBaseID(C4ID.identify(string: "base"))
            .removeDir("mydir")
            .build()

        let removals = m.removals
        #expect(removals.contains("mydir/"))
    }

    @Test("Build from existing manifest")
    func buildFromExisting() {
        var existing = Manifest()
        existing.addEntry(Entry(mode: .file644, name: "existing.txt"))

        let m = ManifestBuilder(manifest: existing)
            .addFile("new.txt")
            .build()

        #expect(m.entries.count == 2)
    }
}
