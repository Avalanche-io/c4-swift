import Testing
import Foundation
@testable import C4M

@Suite("Operations Tests")
struct OperationsTests {

    private func makeManifest(_ names: [String]) -> Manifest {
        var m = Manifest()
        for name in names {
            m.addEntry(Entry(mode: .file644, size: 100, name: name))
        }
        return m
    }

    @Test("Diff: identify additions")
    func diffAdditions() {
        let a = makeManifest(["file1.txt"])
        let b = makeManifest(["file1.txt", "file2.txt"])

        let result = diff(lhs: a, rhs: b)
        #expect(result.added.entries.count == 1)
        #expect(result.added.entries[0].name == "file2.txt")
        #expect(result.removed.entries.isEmpty)
    }

    @Test("Diff: identify removals")
    func diffRemovals() {
        let a = makeManifest(["file1.txt", "file2.txt"])
        let b = makeManifest(["file1.txt"])

        let result = diff(lhs: a, rhs: b)
        #expect(result.removed.entries.count == 1)
        #expect(result.removed.entries[0].name == "file2.txt")
    }

    @Test("Diff: identify modifications")
    func diffModifications() {
        var a = Manifest()
        a.addEntry(Entry(mode: .file644, size: 100, name: "file.txt"))

        var b = Manifest()
        b.addEntry(Entry(mode: .file644, size: 200, name: "file.txt"))

        let result = diff(lhs: a, rhs: b)
        #expect(result.modified.entries.count == 1)
    }

    @Test("Diff: identify same entries")
    func diffSame() {
        let id = C4ID.identify(string: "content")
        var a = Manifest()
        a.addEntry(Entry(mode: .file644, size: 100, name: "file.txt", c4id: id))

        var b = Manifest()
        b.addEntry(Entry(mode: .file644, size: 100, name: "file.txt", c4id: id))

        let result = diff(lhs: a, rhs: b)
        #expect(result.same.entries.count == 1)
        #expect(result.isEmpty)
    }

    @Test("Diff: empty manifests")
    func diffEmpty() {
        let result = diff(lhs: Manifest(), rhs: Manifest())
        #expect(result.isEmpty)
    }

    @Test("Union combines entries")
    func unionCombines() {
        let a = makeManifest(["file1.txt"])
        let b = makeManifest(["file2.txt"])

        let result = union(a, b)
        #expect(result.entries.count == 2)
    }

    @Test("Union deduplicates by name")
    func unionDeduplicates() {
        let a = makeManifest(["file1.txt"])
        let b = makeManifest(["file1.txt", "file2.txt"])

        let result = union(a, b)
        #expect(result.entries.count == 2)
    }

    @Test("Intersect finds common entries")
    func intersectCommon() {
        let a = makeManifest(["file1.txt", "file2.txt"])
        let b = makeManifest(["file2.txt", "file3.txt"])

        let result = intersect(a, b)
        #expect(result.entries.count == 1)
        #expect(result.entries[0].name == "file2.txt")
    }

    @Test("Intersect with disjoint sets")
    func intersectDisjoint() {
        let a = makeManifest(["file1.txt"])
        let b = makeManifest(["file2.txt"])

        let result = intersect(a, b)
        #expect(result.entries.isEmpty)
    }

    @Test("Subtract removes entries")
    func subtractRemoves() {
        let base = makeManifest(["file1.txt", "file2.txt", "file3.txt"])
        let remove = makeManifest(["file2.txt"])

        let result = subtract(remove, from: base)
        #expect(result.entries.count == 2)
        #expect(!result.entries.contains { $0.name == "file2.txt" })
    }

    @Test("Subtract with no overlap")
    func subtractNoOverlap() {
        let base = makeManifest(["file1.txt"])
        let remove = makeManifest(["file2.txt"])

        let result = subtract(remove, from: base)
        #expect(result.entries.count == 1)
    }
}
