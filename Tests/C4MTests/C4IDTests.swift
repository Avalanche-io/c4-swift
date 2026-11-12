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

    // MARK: - A file's C4 ID is its bytes

    /// An independent C4 ID: SHA-512 from /usr/bin/shasum (not CryptoKit),
    /// base58 with the C4 alphabet, "c4" prefix, padded to 90 characters.
    static func independentC4ID(_ data: Data) throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("c4idind-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try data.write(to: tmp)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "512", tmp.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let hex = Array(out.split(separator: " ")[0])
        var digest: [UInt8] = []
        var k = 0
        while k + 1 < hex.count {
            digest.append(UInt8(String(hex[k...k + 1]), radix: 16)!)
            k += 2
        }
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var num = digest
        var chars: [Character] = []
        while num.contains(where: { $0 != 0 }) {
            var rem = 0
            var next: [UInt8] = []
            for b in num {
                let acc = rem * 256 + Int(b)
                let q = acc / 58
                rem = acc % 58
                if !next.isEmpty || q != 0 { next.append(UInt8(q)) }
            }
            chars.append(alphabet[rem])
            num = next
        }
        let body = String(chars.reversed())
        return "c4" + String(repeating: "1", count: 88 - body.count) + body
    }

    static func nestedManifest() -> Manifest {
        var m = Manifest()
        m.addEntry(Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: 1700000000), size: 50,
                         name: "README.md", c4id: C4ID.identify(string: "readme content")))
        m.addEntry(Entry(mode: .dir755, timestamp: Date(timeIntervalSince1970: 1700000000), size: -1, name: "src/"))
        m.addEntry(Entry(mode: .file644, timestamp: Date(timeIntervalSince1970: 1700000000), size: 100,
                         name: "main.swift", c4id: C4ID.identify(string: "main content"), depth: 1))
        m.canonicalize()
        return m
    }

    @Test("the independent encoder is right")
    func independentEncoder() throws {
        #expect(try Self.independentC4ID(Data()) ==
            "c459dsjfscH38cYeXXYogktxf4Cd9ibshE3BHUo6a58hBXmRQdZrAkZzsWcbWtDg5oQstpDuni4Hirj75GEmTc1sFT")
    }

    @Test("identify(url:) gives a c4m file its byte ID, under any name")
    func identifyURLIsBytes() async throws {
        let m = Self.nestedManifest()
        let pretty = Data(m.marshalPretty().utf8)
        let canonical = Data(m.marshal().utf8)
        #expect(pretty != canonical, "the pretty form is not canonical")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("c4id-urls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (name, data) in [("tree.c4m", pretty), ("tree.bin", pretty), ("tree.txt", pretty), ("canon.c4m", canonical)] {
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            let got = try await C4ID.identify(url: url)
            #expect(got.string == (try Self.independentC4ID(data)), "\(name): identify(url:) is not the byte ID")
        }
    }

    @Test("identify(data:) is the byte ID; the description ID is computeC4ID")
    func identifyDataAndDescription() throws {
        let m = Self.nestedManifest()
        let pretty = Data(m.marshalPretty().utf8)
        let canonical = Data(m.marshal().utf8)
        #expect(C4ID.identify(data: pretty).string == (try Self.independentC4ID(pretty)))
        #expect(C4ID.identify(data: canonical).string == (try Self.independentC4ID(canonical)))
        // Two files, two byte IDs; one description, one description ID.
        let a = try Manifest.unmarshal(pretty).computeC4ID()
        let b = try Manifest.unmarshal(canonical).computeC4ID()
        #expect(a == b)
        #expect(a != C4ID.identify(data: pretty))
    }
}
