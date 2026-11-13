import Testing
import Foundation
@testable import C4M

/// Cross-implementation chain-grammar conformance vector (erratum 2026-07-13,
/// amended 2026-11-08). The fixtures under ChainVector/ are byte-identical
/// copies of the Go reference repo's c4m/testdata/chain-vector/ (see its
/// README.md).
///
/// Shared fixture: C4M SPECIFICATION "No Closing Validator" / C4M-STANDARD
/// §10.5 and §10.7. Checkpoints name the ACCUMULATED manifest state, and a
/// resolving decoder rejects any mismatch. A chain ends on its last entry
/// line: a bare C4 ID at end of input is a format error (ruled 2026-11-08).
/// The fixtures are byte-stable; the 2026-11-08 removal of the trailing ID
/// line is the one exception.
@Suite("Chain Vector Conformance")
struct ChainVectorTests {

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "ChainVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func resolvedRootID() throws -> String {
        try fixture("resolved-root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every reader entry point the package exposes. All four go through
    /// `Decoder.decode()`; the port has no separate shape-level reader.
    private static let readers: [(String, @Sendable (String) throws -> Manifest)] = [
        ("Manifest.unmarshal(String)", { try Manifest.unmarshal($0) }),
        ("Manifest.unmarshal(Data)", { try Manifest.unmarshal(Data($0.utf8)) }),
        ("Decoder(string:).decode()", { var d = Decoder(string: $0); return try d.decode() }),
        ("Decoder(data:).decode()", { var d = Decoder(data: Data($0.utf8)); return try d.decode() }),
    ]

    /// Decode through every reader, expecting `trailingID` on `line`.
    private static func expectTrailingID(_ input: String, line: Int) {
        for (name, read) in readers {
            do {
                _ = try read(input)
                Issue.record("\(name): expected trailingID, but decode succeeded")
            } catch let error as C4MError {
                guard case .trailingID(let got) = error else {
                    Issue.record("\(name): expected trailingID, got \(error)")
                    continue
                }
                #expect(got == line, "\(name): trailing ID reported on line \(got), want \(line)")
            } catch {
                Issue.record("\(name): expected C4MError.trailingID, got \(error)")
            }
        }
    }

    @Test("vector.c4m resolves to exactly the pinned root ID")
    func vectorResolves() throws {
        let input = try Self.fixture("vector", "c4m")
        let expected = try Self.resolvedRootID()
        for (name, read) in Self.readers {
            #expect(try read(input).computeC4ID().string == expected, "\(name)")
        }
    }

    // A resolving decoder verifies the bare ID as a checkpoint before it
    // reaches end of input, so a WRONG trailing ID is a checkpoint mismatch,
    // as Go's resolving decoder reports. The trailing-ID error is pinned by
    // the next test, on a trailing ID that verifies.
    @Test("bad-validator.c4m is rejected (checkpoint mismatch before end of input)")
    func badValidatorRejected() throws {
        let input = try Self.fixture("bad-validator", "c4m")
        do {
            _ = try Manifest.unmarshal(input)
            Issue.record("expected rejection, but decode succeeded")
        } catch let error as C4MError {
            guard case .patchIDMismatch = error else {
                Issue.record("expected patchIDMismatch, got \(error)")
                return
            }
        }
    }

    @Test("vector.c4m plus its own resolved root ID is refused as a trailing ID, by every reader")
    func vectorWithTrailingIDRefused() throws {
        let vector = try Self.fixture("vector", "c4m")
        let lines = vector.split(separator: "\n").count
        let withID = vector + (try Self.resolvedRootID()) + "\n"
        Self.expectTrailingID(withID, line: lines + 1)
        // Blank lines after the ID do not end the stream on an entry.
        Self.expectTrailingID(withID + "\n\n", line: lines + 1)
        // No final newline: still the same line.
        Self.expectTrailingID(String(withID.dropLast()), line: lines + 1)
    }

    @Test("the trailing-ID error says how to fix the file")
    func trailingIDMessage() {
        let text = C4MError.trailingID(4).description
        #expect(text == "c4m: a bare C4 ID ends the file; a c4m file never ends with its own ID (line 4): delete that line, or rewrite the file with `c4 id FILE.c4m > fixed.c4m`")
    }

    @Test("a trailing ID after an external base reference is refused too")
    func trailingIDAfterBaseRefused() throws {
        // Verification defers after an external base, but the shape is
        // still a format error.
        let root = try Self.resolvedRootID()
        let entry = "-rw-r--r-- 2026-01-02T03:04:06Z 5 b.txt c42jd8KUQG9DKppN1qt5aWS3PAmdPmNutXyVTb8H123FcuU3shPxpUXsVdcouSALZ4PaDvMYzQSMYCWkb6rop9zhDa"
        Self.expectTrailingID("\(root)\n\(entry)\n\(root)\n", line: 3)
    }

    @Test("a file that is only a first-line base reference is not a trailing ID")
    func baseOnlyIsNotTrailing() throws {
        let root = try Self.resolvedRootID()
        for (name, read) in Self.readers {
            let m = try read(root + "\n")
            #expect(m.base?.string == root, "\(name)")
            #expect(m.entries.isEmpty, "\(name)")
        }
    }

    @Test("consecutive checkpoints followed by a patch are still accepted")
    func consecutiveCheckpointsThenPatch() throws {
        let lines = try Self.fixture("vector", "c4m").split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        let repeated = [lines[0], lines[1], lines[1], lines[2]].joined(separator: "\n") + "\n"
        let expected = try Self.resolvedRootID()
        for (name, read) in Self.readers {
            #expect(try read(repeated).computeC4ID().string == expected, "\(name)")
        }
    }

    @Test("bad-checkpoint.c4m is rejected (interior checkpoint mismatch)")
    func badCheckpointRejected() throws {
        let input = try Self.fixture("bad-checkpoint", "c4m")
        do {
            _ = try Manifest.unmarshal(input)
            Issue.record("expected rejection, but decode succeeded")
        } catch let error as C4MError {
            guard case .patchIDMismatch = error else {
                Issue.record("expected patchIDMismatch, got \(error)")
                return
            }
        }
    }
}
