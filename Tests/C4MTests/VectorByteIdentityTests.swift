import Testing
import Foundation
import CryptoKit
@testable import C4M

/// Byte identity over every shared vector this port vendors. Each `.c4m`
/// file is decoded and re-encoded canonically, and the SHA-512 of the
/// output is compared with the input's (CryptoKit's SHA-512, not the port's
/// C4 ID code). A c4m file's byte ID is a C4 ID, so a round trip that
/// changes a canonical file's bytes changes its ID: nothing compared bytes
/// before, which is how such a loss could go unseen (decided 2026-11-13 by
/// the release lead; reversible).
///
/// Every file is classified as c4 core's Go reference classifies it
/// (measured 2026-11-13 on c4 7a6ba94), and a file in a vector directory
/// that the table does not name fails, so a new vector cannot be skipped.
/// The one place this port differs from Go is SafeNameVector/names.c4m: see
/// `classes` below.
@Suite("Vector Byte Identity")
struct VectorByteIdentityTests {

    enum Class {
        /// The library wrote it canonically: re-encoding gives the same bytes.
        case stable
        /// Decodes, but is not canonical text, by design (the reason).
        case nonCanonical(String)
        /// Refused on decode, by design (the reason).
        case rejected(String)
    }

    static let pretty = "pretty form (the vector's README: the same tree, written by the pretty encoder)"
    static let zeroSpelled = "a null size spelled 0 (the vector's README: a 0 beside a C4 ID other than the empty content's is null, re-encoded as -)"
    static let legacy = "legacy null mode: ten dashes, which a release through 1.0.21 wrote for a null mode (re-encoded as -)"
    static let chain = "a patch chain, which decodes to its resolved state (the vector's README)"
    static let damaged = "a damaged line (DamagedLineVector README)"
    static let nameEscape = "a name a writer never produces (NameEscapeVector README)"
    static let nameRule = "a path where an entry name belongs (NameRuleVector README)"

    static let classes: [String: Class] = [
        "BackslashNameVector/canonical.c4m": .stable,
        "BackslashNameVector/patch.c4m": .stable,
        "BackslashNameVector/pretty.c4m": .nonCanonical(pretty),

        "ChainVector/vector.c4m": .nonCanonical(chain),
        "ChainVector/bad-checkpoint.c4m": .rejected("an interior checkpoint that does not match the accumulated state (ChainVector README)"),
        "ChainVector/bad-validator.c4m": .rejected("a bare ID at EOF that mismatches the accumulated state, and ends the file (ChainVector README)"),

        "ChildlessDirVector/normalized.c4m": .stable,
        "ChildlessDirVector/stated.c4m": .stable,

        "DamagedLineVector/ok.c4m": .stable,
        "DamagedLineVector/id-89.c4m": .rejected(damaged),
        "DamagedLineVector/id-91.c4m": .rejected(damaged),
        "DamagedLineVector/id-bad-char.c4m": .rejected(damaged),
        "DamagedLineVector/mode-bad-char.c4m": .rejected(damaged),
        "DamagedLineVector/mode-sticky-letter-misplaced.c4m": .rejected(damaged),
        "DamagedLineVector/mode-wrong-letter.c4m": .rejected(damaged),
        "DamagedLineVector/size-junk.c4m": .rejected(damaged),
        "DamagedLineVector/size-null-junk.c4m": .rejected(damaged),
        "DamagedLineVector/time-impossible.c4m": .rejected(damaged),

        "DeepenVector/deepen.c4m": .nonCanonical(chain),
        "DeepenVector/remove.c4m": .nonCanonical(chain),

        "Legacy/ten-dash-null-1.0.21.c4m": .nonCanonical(legacy),

        "LinkTargetVector/canonical.c4m": .stable,
        "LinkTargetVector/patch.c4m": .stable,
        "LinkTargetVector/pretty.c4m": .nonCanonical(pretty),

        "NameEscapeVector/ok-dir.c4m": .stable,
        "NameEscapeVector/ok-escaped.c4m": .stable,
        "NameEscapeVector/ok-file.c4m": .stable,
        "NameEscapeVector/ok-indent-3.c4m": .nonCanonical("written with SetIndent(3): any consistent indent unit reads, and canonical output indents by 2 (NameEscapeVector README)"),
        "NameEscapeVector/dir-unescaped-space.c4m": .rejected(nameEscape),
        "NameEscapeVector/file-damaged-id-field.c4m": .rejected(nameEscape),
        "NameEscapeVector/file-raw-control.c4m": .rejected(nameEscape),
        "NameEscapeVector/file-raw-quote.c4m": .rejected(nameEscape),
        "NameEscapeVector/file-raw-tab.c4m": .rejected(nameEscape),
        "NameEscapeVector/file-unescaped-space.c4m": .rejected(nameEscape),

        "NameRuleVector/ok-dir.c4m": .stable,
        "NameRuleVector/ok-file.c4m": .stable,
        "NameRuleVector/dir-dot.c4m": .rejected(nameRule),
        "NameRuleVector/dir-dotdot.c4m": .rejected(nameRule),
        "NameRuleVector/dir-double-slash.c4m": .rejected(nameRule),
        "NameRuleVector/dir-nested.c4m": .rejected(nameRule),
        "NameRuleVector/dir-root.c4m": .rejected(nameRule),
        "NameRuleVector/file-dot.c4m": .rejected(nameRule),
        "NameRuleVector/file-dotdot-inside.c4m": .rejected(nameRule),
        "NameRuleVector/file-dotdot.c4m": .rejected(nameRule),
        "NameRuleVector/file-leading-slash.c4m": .rejected(nameRule),
        "NameRuleVector/file-sub.c4m": .rejected(nameRule),
        "NameRuleVector/file-trailing-path.c4m": .rejected(nameRule),

        "NullSizeVector/canonical.c4m": .stable,
        "NullSizeVector/zero-spelled.c4m": .nonCanonical(zeroSpelled),

        // Go round-trips this file byte for byte; this port refuses it. Its
        // README, decided 2026-11-13 by the release lead (reversible): names
        // that are not valid UTF-8 "are refused, naming the line, by
        // implementations whose string type cannot hold them (c4ts,
        // c4m-swift), for 1.x". `safeNameRest` checks every other line.
        "SafeNameVector/names.c4m": .rejected("four names are not valid UTF-8, which a Swift String cannot hold (SafeNameVector README, decided 2026-11-13)"),

        "SequenceNullSizeVector/folded.c4m": .stable,
        "SequenceNullSizeVector/frames.c4m": .stable,
        "SequenceNullSizeVector/frames-zero-spelled.c4m": .nonCanonical(zeroSpelled),

        "UnicodeNameVector/canonical.c4m": .stable,
        "UnicodeNameVector/nfc-nfd-chain.c4m": .nonCanonical(chain),
        "UnicodeNameVector/pretty.c4m": .nonCanonical(pretty),

        "ZeroNullVector/canonical.c4m": .stable,
        "ZeroNullVector/pretty.c4m": .nonCanonical(pretty),
    ]

    private static var root: URL { Bundle.module.resourceURL! }

    private static func bytes(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    private static func roundTrip(_ data: Data) throws -> Data {
        Data(try Manifest.unmarshal(data).marshal().utf8)
    }

    @Test("every vector file is classified, and every classified file exists")
    func everyFileClassified() throws {
        let fm = FileManager.default
        var found: Set<String> = []
        for dir in try fm.contentsOfDirectory(atPath: Self.root.path) {
            var isDir: ObjCBool = false
            let url = Self.root.appendingPathComponent(dir)
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            for f in try fm.contentsOfDirectory(atPath: url.path) where f.hasSuffix(".c4m") {
                found.insert("\(dir)/\(f)")
            }
        }
        #expect(found.subtracting(Self.classes.keys).sorted() == [], "unclassified vector files")
        #expect(Set(Self.classes.keys).subtracting(found).sorted() == [], "classified files missing")
    }

    @Test("decode and canonical re-encode, compared by SHA-512", arguments: classes.keys.sorted())
    func byteIdentity(path: String) throws {
        let input = try Self.bytes(path)
        switch Self.classes[path]! {
        case .stable:
            let output = try Self.roundTrip(input)
            #expect(SHA512.hash(data: output) == SHA512.hash(data: input), "\(path) re-encodes to different bytes")
        case .nonCanonical(let why):
            // Not canonical, so the bytes differ; the canonical text it
            // decodes to is itself byte-stable.
            let output = try Self.roundTrip(input)
            #expect(SHA512.hash(data: output) != SHA512.hash(data: input), "\(path) is now canonical; reclassify it (was: \(why))")
            #expect(SHA512.hash(data: try Self.roundTrip(output)) == SHA512.hash(data: output), "\(path): its canonical form is not stable")
        case .rejected(let why):
            #expect(throws: (any Error).self, "\(path) decoded (expected refusal: \(why))") {
                _ = try Manifest.unmarshal(input)
            }
        }
    }

    /// SafeNameVector/names.c4m less its four names that are not UTF-8 (the
    /// file is flat, one entry per line) still round-trips byte for byte, so
    /// the refusal above hides no fault in the other 27 names.
    @Test("SafeNameVector/names.c4m less its invalid-UTF-8 names round-trips byte for byte")
    func safeNameRest() throws {
        let text = String(decoding: try Self.bytes("SafeNameVector/names.c4m"), as: UTF8.self)
        let invalid = ["invalid-ff", "lone-continuation", "overlong-nul", "surrogate"]
        let lines = text.split(separator: "\n").filter { l in !invalid.contains { l.contains(" \($0)-") } }
        #expect(lines.count == 27)
        let rest = Data((lines.joined(separator: "\n") + "\n").utf8)
        #expect(SHA512.hash(data: try Self.roundTrip(rest)) == SHA512.hash(data: rest))
    }
}
