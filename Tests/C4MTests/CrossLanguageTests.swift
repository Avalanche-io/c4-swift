import Testing
import Foundation
@testable import C4M

/// Convert a hex string to Data.
private func hexToData(_ hex: String) -> Data {
    var data = Data()
    var i = hex.startIndex
    while i < hex.endIndex {
        let j = hex.index(i, offsetBy: 2)
        let byte = UInt8(hex[i..<j], radix: 16)!
        data.append(byte)
        i = j
    }
    return data
}

/// Convert Data to a lowercase hex string.
private func dataToHex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

// MARK: - JSON Structures

private struct TestVectors: Decodable {
    let single_ids: [SingleIDVector]
    let tree_ids: [TreeIDVector]
    let manifest_vectors: [ManifestVector]
}

private struct SingleIDVector: Decodable {
    let input_repr: String
    let input_bytes_hex: String
    let c4id: String
    let digest_hex: String
}

private struct TreeIDVector: Decodable {
    let description: String
    let inputs: [String]
    let tree_id: String
}

private struct ManifestVector: Decodable {
    let description: String
    let canonical: String
    let manifest_c4id: String
}

@Suite("Cross-Language Test Vectors")
struct CrossLanguageTests {

    private static func loadVectors() throws -> TestVectors {
        let url = Bundle.module.url(forResource: "known_ids", withExtension: "json", subdirectory: "Vectors")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TestVectors.self, from: data)
    }

    // MARK: - Single IDs

    @Test("single_ids[0]: empty string")
    func singleID0() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[0]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[1]: foo")
    func singleID1() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[1]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[2]: bar")
    func singleID2() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[2]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[3]: baz")
    func singleID3() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[3]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[4]: hello world")
    func singleID4() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[4]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[5]: a")
    func singleID5() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[5]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[6]: b")
    func singleID6() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[6]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[7]: newline")
    func singleID7() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[7]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    @Test("single_ids[8]: null byte")
    func singleID8() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.single_ids[8]
        let input = hexToData(v.input_bytes_hex)
        let id = C4ID.identify(data: input)
        #expect(id.string == v.c4id)
        #expect(dataToHex(Data(id.digest)) == v.digest_hex)
    }

    // MARK: - Tree IDs

    // TODO: c4-swift does not yet have a treeId() function.
    // When tree ID computation is added, uncomment these tests and verify
    // that the tree IDs match the vectors (order-independent hash combination).

    @Test("tree_ids: skipped (no treeId function)")
    func treeIDsSkipped() {
        // Placeholder: verify the vectors load but skip actual tree ID computation.
        // Tree ID tests require a function like:
        //   C4ID.treeID(from: [C4ID]) -> C4ID
        // which sorts the IDs, concatenates their digests, and hashes the result.
    }

    // MARK: - Manifest Vectors

    @Test("manifest_vectors[0]: simple project")
    func manifestVector0() throws {
        let vectors = try Self.loadVectors()
        let v = vectors.manifest_vectors[0]

        let manifest = try Manifest.unmarshal(v.canonical)
        let computedID = manifest.computeC4ID()

        #expect(computedID.string == v.manifest_c4id)
    }
}
