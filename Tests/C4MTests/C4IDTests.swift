import Testing
import Foundation
@testable import C4M

@Suite("C4ID Tests")
struct C4IDTests {

    @Test("void ID is nil")
    func voidIsNil() {
        #expect(C4ID.void.isNil)
    }

    @Test("identify empty data produces consistent ID")
    func identifyEmptyData() {
        let id = C4ID.identify(data: Data())
        #expect(!id.isNil)
        #expect(id.string.hasPrefix("c4"))
        #expect(id.string.count == 90)
    }

    @Test("identify same data produces same ID")
    func identifyDeterministic() {
        let data = Data("hello world".utf8)
        let id1 = C4ID.identify(data: data)
        let id2 = C4ID.identify(data: data)
        #expect(id1 == id2)
    }

    @Test("identify different data produces different IDs")
    func identifyDifferent() {
        let id1 = C4ID.identify(data: Data("hello".utf8))
        let id2 = C4ID.identify(data: Data("world".utf8))
        #expect(id1 != id2)
    }

    @Test("roundtrip: encode then parse")
    func roundtrip() {
        let id = C4ID.identify(data: Data("test content".utf8))
        let str = id.string
        let parsed = C4ID(str)
        #expect(parsed != nil)
        #expect(parsed! == id)
        #expect(parsed!.string == str)
    }

    @Test("parse invalid strings returns nil")
    func parseInvalid() {
        #expect(C4ID("") == nil)
        #expect(C4ID("too short") == nil)
        #expect(C4ID("xx" + String(repeating: "1", count: 88)) == nil) // wrong prefix
        #expect(C4ID("c4" + String(repeating: "0", count: 88)) == nil) // 0 is not in base58
    }

    @Test("C4ID is Comparable")
    func comparable() {
        let id1 = C4ID.identify(data: Data("aaa".utf8))
        let id2 = C4ID.identify(data: Data("bbb".utf8))
        // Just verify the comparison is consistent
        if id1 < id2 {
            #expect(!(id2 < id1))
        } else {
            #expect(id2 < id1 || id1 == id2)
        }
    }

    @Test("C4ID is Hashable")
    func hashable() {
        let id = C4ID.identify(data: Data("test".utf8))
        var set = Set<C4ID>()
        set.insert(id)
        set.insert(id) // duplicate
        #expect(set.count == 1)
    }

    @Test("C4ID JSON Codable roundtrip")
    func codable() throws {
        let id = C4ID.identify(data: Data("test".utf8))
        let encoded = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(C4ID.self, from: encoded)
        #expect(decoded == id)
    }

    @Test("Void C4ID encodes as empty string")
    func codableVoid() throws {
        let encoded = try JSONEncoder().encode(C4ID.void)
        let str = String(data: encoded, encoding: .utf8)!
        #expect(str == "\"\"")
    }

    @Test("identify string convenience")
    func identifyString() {
        let id1 = C4ID.identify(string: "hello")
        let id2 = C4ID.identify(data: Data("hello".utf8))
        #expect(id1 == id2)
    }

    @Test("known C4 ID value: empty string")
    func knownEmptyString() {
        // The C4 ID of the empty string is well-known
        let id = C4ID.identify(data: Data())
        #expect(id.string.hasPrefix("c4"))
        #expect(id.string.count == 90)
        // Verify it parses back correctly
        let parsed = C4ID(id.string)
        #expect(parsed == id)
    }

    // MARK: - c4m-aware identification

    @Test("pretty and canonical c4m produce same ID via identifyC4mAware")
    func c4mAwarePrettyAndCanonical() throws {
        // Build a manifest with known entries
        var manifest = Manifest()
        manifest.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 42,
            name: "hello.txt",
            c4id: C4ID.identify(string: "hello content")
        ))
        manifest.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1700000100),
            size: 99,
            name: "world.txt",
            c4id: C4ID.identify(string: "world content")
        ))

        // Get canonical and pretty forms
        let canonical = manifest.marshal()
        let pretty = manifest.marshalPretty()

        // They should differ in formatting
        #expect(canonical != pretty, "canonical and pretty forms should differ in formatting")

        // Both should produce the same C4 ID via c4m-aware identification
        let canonicalID = C4ID.identifyC4mAware(data: Data(canonical.utf8))
        let prettyID = C4ID.identifyC4mAware(data: Data(pretty.utf8))
        #expect(canonicalID == prettyID, "pretty and canonical c4m should have the same C4 ID")

        // The c4m-aware ID should equal the raw hash of canonical bytes
        let rawCanonicalID = C4ID.identify(data: Data(canonical.utf8))
        #expect(canonicalID == rawCanonicalID, "c4m-aware ID should match raw hash of canonical bytes")
    }

    @Test("c4m-aware identification falls back to raw bytes for non-c4m data")
    func c4mAwareFallback() {
        let data = Data("this is not a c4m file".utf8)
        let rawID = C4ID.identify(data: data)
        let awareID = C4ID.identifyC4mAware(data: data)
        #expect(rawID == awareID, "non-c4m data should produce same ID regardless of method")
    }

    @Test("looksLikeC4m detects c4m-like content")
    func looksLikeC4mDetection() {
        // Valid c4m-like first lines
        #expect(C4ID.looksLikeC4m(Data("-rw-r--r-- 0 42 file.txt -\n".utf8)))
        #expect(C4ID.looksLikeC4m(Data("drwxr-xr-x 0 0 dir/ -\n".utf8)))
        #expect(C4ID.looksLikeC4m(Data("lrwxrwxrwx 0 0 link -> target -\n".utf8)))
        #expect(C4ID.looksLikeC4m(Data("- 0 42 file.txt -\n".utf8)))

        // Leading blank lines should be skipped
        #expect(C4ID.looksLikeC4m(Data("\n\n-rw-r--r-- 0 42 file.txt -\n".utf8)))

        // Non-c4m content
        #expect(!C4ID.looksLikeC4m(Data("hello world".utf8)))
        #expect(!C4ID.looksLikeC4m(Data("".utf8)))
        #expect(!C4ID.looksLikeC4m(Data("{ json }".utf8)))
    }

    @Test("c4m-aware with directory entries produces same ID from pretty and canonical")
    func c4mAwareWithDirectories() throws {
        var manifest = Manifest()
        manifest.addEntry(Entry(
            mode: .dir755,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: -1,
            name: "src/"
        ))
        manifest.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 100,
            name: "main.swift",
            c4id: C4ID.identify(string: "main content"),
            depth: 1
        ))
        manifest.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 50,
            name: "README.md",
            c4id: C4ID.identify(string: "readme content")
        ))

        let canonical = manifest.marshal()
        let pretty = manifest.marshalPretty()

        #expect(canonical != pretty)

        let canonicalID = C4ID.identifyC4mAware(data: Data(canonical.utf8))
        let prettyID = C4ID.identifyC4mAware(data: Data(pretty.utf8))
        #expect(canonicalID == prettyID)
    }

    @Test("identify(url:) uses c4m-aware for .c4m files")
    func identifyURLc4mAware() async throws {
        var manifest = Manifest()
        manifest.addEntry(Entry(
            mode: .file644,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            size: 42,
            name: "test.txt",
            c4id: C4ID.identify(string: "test")
        ))

        let pretty = manifest.marshalPretty()
        let canonical = manifest.marshal()

        // Write pretty form to a .c4m file
        let tmpDir = FileManager.default.temporaryDirectory
        let prettyURL = tmpDir.appendingPathComponent("test-\(UUID().uuidString).c4m")
        let canonicalURL = tmpDir.appendingPathComponent("test-\(UUID().uuidString).c4m")
        defer {
            try? FileManager.default.removeItem(at: prettyURL)
            try? FileManager.default.removeItem(at: canonicalURL)
        }
        try Data(pretty.utf8).write(to: prettyURL)
        try Data(canonical.utf8).write(to: canonicalURL)

        let prettyID = try await C4ID.identify(url: prettyURL)
        let canonicalID = try await C4ID.identify(url: canonicalURL)
        #expect(prettyID == canonicalID, "identify(url:) should produce same ID for pretty and canonical .c4m files")
    }
}
