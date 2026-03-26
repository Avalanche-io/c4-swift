import Foundation
import CryptoKit

/// The base-58 character set used by C4 (excludes 0, O, I, l to avoid confusion).
private let base58Charset: [Character] = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
private let base58CharsetBytes: [UInt8] = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

/// Reverse lookup table: ASCII byte -> base-58 digit value (0xFF = invalid).
private let base58Lookup: [UInt8] = {
    var lut = [UInt8](repeating: 0xFF, count: 256)
    for (i, c) in base58CharsetBytes.enumerated() {
        lut[Int(c)] = UInt8(i)
    }
    return lut
}()

/// A C4 identifier: 90 characters, always starting with "c4", encoding a SHA-512 hash in base-58.
public struct C4ID: Sendable, Hashable, Codable, CustomStringConvertible {

    /// The raw 64-byte SHA-512 digest.
    public let digest: [UInt8]  // exactly 64 bytes

    /// The canonical 90-character string representation.
    public var description: String { string }

    /// True if every byte of the digest is zero (the void/nil ID).
    public var isNil: Bool { digest.allSatisfy { $0 == 0 } }

    /// The cached string representation.
    public let string: String

    // MARK: - Initialisers

    /// Create a C4ID from a raw 64-byte digest.
    public init(digest: [UInt8]) {
        precondition(digest.count == 64, "C4 digest must be exactly 64 bytes")
        self.digest = digest
        self.string = Self.encode(digest)
    }

    /// Parse a 90-character C4 ID string.
    public init?(_ string: String) {
        guard let d = Self.decode(string) else { return nil }
        self.digest = d
        self.string = string
    }

    /// The nil (all-zero) C4 ID.
    public static let void = C4ID(digest: [UInt8](repeating: 0, count: 64))

    // MARK: - Identification

    /// Compute the C4 ID of the given data.
    public static func identify(data: Data) -> C4ID {
        let hash = SHA512.hash(data: data)
        return C4ID(digest: Array(hash))
    }

    /// Compute the C4 ID of the given string (UTF-8 encoded).
    public static func identify(string: String) -> C4ID {
        identify(data: Data(string.utf8))
    }

    /// Compute the C4 ID of the given data, with c4m-aware canonicalization.
    ///
    /// If the data parses as a valid c4m file, the ID is computed from the
    /// canonical form rather than the raw bytes. This ensures that a
    /// pretty-printed c4m and its canonical equivalent produce the same ID.
    ///
    /// If the data does not parse as c4m, the ID is computed from raw bytes.
    public static func identifyC4mAware(data: Data) -> C4ID {
        if let canonical = canonicalizeC4mData(data) {
            return identify(data: Data(canonical.utf8))
        }
        return identify(data: data)
    }

    /// Compute the C4 ID of the file at the given URL.
    ///
    /// For `.c4m` files or data that looks like c4m content, the ID is
    /// computed from the canonical form (c4m-aware identification).
    /// For all other files, the ID is computed from raw bytes.
    public static func identify(url: URL) async throws -> C4ID {
        let data = try Data(contentsOf: url)
        if url.pathExtension == "c4m" || looksLikeC4m(data) {
            return identifyC4mAware(data: data)
        }
        return identify(data: data)
    }

    // MARK: - c4m Detection

    /// Heuristic: check if data looks like a c4m file by inspecting
    /// the first non-blank line. If it starts with a mode character
    /// (-, d, l, p, s, b, c), it might be c4m.
    static func looksLikeC4m(_ data: Data) -> Bool {
        let bytes = Array(data)
        var i = 0
        let n = bytes.count
        // Find first non-blank line
        while i < n {
            // Skip whitespace
            while i < n && (bytes[i] == 0x20 || bytes[i] == 0x09) { i += 1 }
            // Skip empty lines
            if i < n && bytes[i] == 0x0A { i += 1; continue }
            break
        }
        if i >= n { return false }
        let ch = bytes[i]
        // Mode characters: - d l p s b c
        return ch == 0x2D || ch == 0x64 || ch == 0x6C ||
               ch == 0x70 || ch == 0x73 || ch == 0x62 || ch == 0x63
    }

    /// Try to parse data as c4m and return canonical form string.
    /// Returns nil if parsing fails or manifest is empty.
    private static func canonicalizeC4mData(_ data: Data) -> String? {
        guard let manifest = try? Manifest.unmarshal(data),
              !manifest.entries.isEmpty else {
            return nil
        }
        return manifest.marshal()
    }

    // MARK: - Codable

    public init(from decoder: Swift.Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        if s.isEmpty {
            self = .void
            return
        }
        guard let id = C4ID(s) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid C4 ID: \(s)")
        }
        self = id
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        if isNil {
            try container.encode("")
        } else {
            try container.encode(string)
        }
    }

    // MARK: - Base-58 Encoding / Decoding

    /// Encode 64 bytes as a 90-character C4 ID string (c4 prefix + 88 base-58 digits).
    private static func encode(_ bytes: [UInt8]) -> String {
        // Convert bytes to a big integer
        var num = [UInt32]() // big-endian limbs, base 2^32
        for b in bytes {
            // multiply existing number by 256 and add byte
            var carry = UInt64(b)
            for i in (0 ..< num.count).reversed() {
                let product = UInt64(num[i]) * 256 + carry
                num[i] = UInt32(product & 0xFFFF_FFFF)
                carry = product >> 32
            }
            if carry > 0 {
                num.insert(UInt32(carry), at: 0)
            }
        }

        // Repeatedly divide by 58 to get base-58 digits (least significant first)
        var encoded = [UInt8](repeating: base58CharsetBytes[0], count: 90) // fill with '1'
        encoded[0] = UInt8(ascii: "c")
        encoded[1] = UInt8(ascii: "4")

        var pos = 89
        while !num.isEmpty && pos > 1 {
            var remainder = UInt64(0)
            var newNum = [UInt32]()
            for limb in num {
                let acc = remainder << 32 | UInt64(limb)
                let q = acc / 58
                remainder = acc % 58
                if !newNum.isEmpty || q > 0 {
                    newNum.append(UInt32(q))
                }
            }
            encoded[pos] = base58CharsetBytes[Int(remainder)]
            pos -= 1
            num = newNum
        }

        return String(bytes: encoded, encoding: .ascii)!
    }

    /// Decode a 90-character C4 ID string to 64 bytes. Returns nil on invalid input.
    private static func decode(_ string: String) -> [UInt8]? {
        let bytes = Array(string.utf8)
        guard bytes.count == 90, bytes[0] == UInt8(ascii: "c"), bytes[1] == UInt8(ascii: "4") else {
            return nil
        }

        // Convert base-58 digits (positions 2..89) to a big integer
        var num = [UInt32]() // big-endian limbs, base 2^32
        for i in 2 ..< 90 {
            let digit = base58Lookup[Int(bytes[i])]
            if digit == 0xFF { return nil }

            // multiply existing number by 58 and add digit
            var carry = UInt64(digit)
            for j in (0 ..< num.count).reversed() {
                let product = UInt64(num[j]) * 58 + carry
                num[j] = UInt32(product & 0xFFFF_FFFF)
                carry = product >> 32
            }
            if carry > 0 {
                num.insert(UInt32(carry), at: 0)
            }
        }

        // Convert big integer to 64 bytes (big-endian)
        var result = [UInt8](repeating: 0, count: 64)
        var idx = 63
        for limb in num.reversed() {
            var v = limb
            for _ in 0 ..< 4 {
                if idx < 0 { break }
                result[idx] = UInt8(v & 0xFF)
                v >>= 8
                idx -= 1
            }
        }

        return result
    }

    // MARK: - Sum and Tree

    /// Compute the order-independent sum of two C4 IDs.
    ///
    /// The two digests are sorted so the smaller comes first, concatenated
    /// into 128 bytes, and SHA-512 hashed to produce a new C4 ID.
    /// If the two IDs are identical, the ID is returned as-is.
    public func sum(_ other: C4ID) -> C4ID {
        if self == other { return self }
        let (a, b) = digest.lexicographicallyPrecedes(other.digest)
            ? (digest, other.digest)
            : (other.digest, digest)
        let hash = SHA512.hash(data: a + b)
        return C4ID(digest: Array(hash))
    }

    /// Compute the tree ID of an array of C4 IDs.
    ///
    /// The algorithm sorts the IDs by raw digest bytes, deduplicates them,
    /// then builds a binary tree bottom-up: adjacent pairs are summed
    /// (order-independent) and an odd trailing ID carries forward.
    /// Returns the single root ID. Returns `C4ID.void` for an empty array.
    public static func treeID(from ids: [C4ID]) -> C4ID {
        if ids.isEmpty { return .void }

        // Sort by digest bytes
        var sorted = ids.sorted()

        // Deduplicate
        if sorted.count > 1 {
            var j = 1
            for i in 1..<sorted.count {
                if sorted[i] != sorted[j - 1] {
                    sorted[j] = sorted[i]
                    j += 1
                }
            }
            sorted = Array(sorted.prefix(j))
        }

        if sorted.count == 1 { return sorted[0] }

        // Build tree bottom-up
        var level = sorted
        while level.count > 1 {
            var next: [C4ID] = []
            var i = 0
            while i + 1 < level.count {
                next.append(level[i].sum(level[i + 1]))
                i += 2
            }
            if i < level.count {
                // Odd one out carries forward
                next.append(level[i])
            }
            level = next
        }
        return level[0]
    }
}

// MARK: - Comparable

extension C4ID: Comparable {
    public static func < (lhs: C4ID, rhs: C4ID) -> Bool {
        lhs.digest.lexicographicallyPrecedes(rhs.digest)
    }
}
