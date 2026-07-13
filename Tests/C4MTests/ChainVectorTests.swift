import Testing
import Foundation
@testable import C4M

/// Cross-implementation chain-grammar conformance vector (erratum 2026-07-13).
///
/// Shared fixture: C4M SPECIFICATION "The Closing Validator" / C4M-STANDARD
/// §10.5. Checkpoints name the ACCUMULATED manifest state; a bare C4 ID at
/// EOF is the mandatory-verified closing validator; a resolving decoder
/// rejects any mismatch. Every c4m implementation MUST pass all three cases.
/// The fixtures are byte-stable — do not regenerate them.
@Suite("Chain Vector Conformance")
struct ChainVectorTests {

    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "ChainVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("vector.c4m resolves to exactly the pinned root ID")
    func vectorResolves() throws {
        let input = try Self.fixture("vector", "c4m")
        let expected = try Self.fixture("resolved-root-id", "txt")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let manifest = try Manifest.unmarshal(input)
        #expect(manifest.computeC4ID().string == expected)
    }

    @Test("bad-validator.c4m is rejected (closing validator mismatch)")
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
