/// A name or path compared as its UTF-8 bytes.
///
/// Swift `String` equality, ordering and hashing use canonical equivalence:
/// the NFC and NFD spellings of `café.txt` compare equal and hash alike.
/// c4m names are bytes, so those are two names, and Go and the other ports
/// keep both. Every map, set and comparison of names or paths in this
/// package goes through `ByteKey` (or `sameBytes`), never through `String`
/// itself. Through 1.0.25 a description holding both spellings lost one on
/// encode, and a patch adding the other spelling merged into the first
/// (unicode-name vector, 2026-11-11).
struct ByteKey: Hashable, Comparable, Sendable {
    let bytes: [UInt8]

    init(_ s: String) { bytes = Array(s.utf8) }
    init(bytes: [UInt8]) { self.bytes = bytes }

    /// The key's text.
    var string: String { String(decoding: bytes, as: UTF8.self) }

    /// Byte order, as Go's string comparison.
    static func < (a: ByteKey, b: ByteKey) -> Bool {
        a.bytes.lexicographicallyPrecedes(b.bytes)
    }

    func hasPrefix(_ p: ByteKey) -> Bool { bytes.starts(with: p.bytes) }

    /// True if the key ends in "/", a directory's marker.
    var isDirPath: Bool { bytes.last == 0x2F }
}

/// True if a and b are the same bytes (not merely canonically equivalent).
func sameBytes(_ a: String, _ b: String) -> Bool {
    a.utf8.elementsEqual(b.utf8)
}
