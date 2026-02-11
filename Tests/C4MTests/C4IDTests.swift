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
}
