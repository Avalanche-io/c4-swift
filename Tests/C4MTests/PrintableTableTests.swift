import Testing
import Foundation
@testable import C4M

/// SafeName's printable test is pinned to Unicode 17.0.0 (c4 #149; decided
/// 2026-11-13 by the release lead; reversible). The table is generated from
/// SafeNameVector/printable-17.0.0.txt, a byte-for-byte copy of c4 core's
/// shared file, by Scripts/gen_printable.swift.
@Suite("Printable table pinned to Unicode 17.0.0")
struct PrintableTableTests {

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "SafeNameVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("the table is the shared text file, range by range")
    func tableMatchesSharedFile() throws {
        let version = try Self.fixture("unicode-version", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(version == "17.0.0")
        #expect(printableUnicodeVersion == version)

        var file: [(UInt32, UInt32)] = []
        for line in try Self.fixture("printable-\(version)", "txt").split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let parts = line.components(separatedBy: "..")
            let lo = try #require(parts.count == 2 ? UInt32(parts[0], radix: 16) : nil, "bad line \(line)")
            let hi = try #require(UInt32(parts[1], radix: 16), "bad line \(line)")
            file.append((lo, hi))
        }
        #expect(file.count == 741)
        #expect(file.count == printableRanges.count)
        for (i, (f, t)) in zip(file, printableRanges).enumerated() {
            #expect(f.0 == t.0 && f.1 == t.1, "range \(i): file \(f), table \(t)")
        }
    }

    @Test("lookup agrees with the ranges at every boundary")
    func lookupBoundaries() {
        for (i, r) in printableRanges.enumerated() {
            #expect(isPrintableScalar(Unicode.Scalar(r.0)!))
            #expect(isPrintableScalar(Unicode.Scalar(r.1)!))
            if i > 0, r.0 - printableRanges[i - 1].1 > 1, let gap = Unicode.Scalar(r.0 - 1) {
                #expect(!isPrintableScalar(gap), "U+\(String(r.0 - 1, radix: 16)) lies between ranges")
            }
        }
        #expect(!isPrintableScalar("\u{0}"))
        #expect(!isPrintableScalar("\u{1F}"))
        #expect(isPrintableScalar(" "))
        #expect(!isPrintableScalar("\u{7F}"))
        #expect(!isPrintableScalar("\u{10FFFF}"))
    }

    /// U+0870 was assigned in Unicode 14.0 and is printable in the table;
    /// U+0378 is unassigned in 17.0.0 and stays encoded even on a runtime
    /// that assigns it later. Neither answer comes from the runtime.
    @Test("SafeName does not follow the runtime's Unicode")
    func doesNotFollowRuntime() {
        #expect(safeName("a\u{0870}b") == "a\u{0870}b")
        let encoded = safeName("a\u{0378}b")
        #expect(encoded != "a\u{0378}b")
        #expect(encoded == "a\u{00A4}\u{28CD}\u{28B8}\u{00A4}b")
        #expect(unsafeName(encoded) == "a\u{0378}b")
    }
}
