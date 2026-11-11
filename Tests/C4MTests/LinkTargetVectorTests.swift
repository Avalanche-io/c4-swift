import Testing
import Foundation
@testable import C4M

/// Cross-implementation conformance for link lines that look like the C4 ID
/// field (2026-11-10). The fixtures under LinkTargetVector/ are byte-identical
/// copies of the Go reference repo's c4m/testdata/link-target-vector/; its
/// README states what every implementation MUST decode.
///
/// - After a link operator, a single field that is `-` or a C4 ID is an
///   ungrouped hard link's ID field; two fields are a target and the ID
///   field, even when the target starts with "c4" (under a null mode, as
///   views carry links). This decoder read such a link as a hard link and
///   dropped its target, with no error.
/// - The pretty form's padding before the ID field is not part of a target
///   (this decoder already had that right; the vector pins it).
struct LinkTargetVectorTests {
    private static func fixture(_ name: String, _ ext: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "LinkTargetVector")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let idText = "c43312d4NsKWQvybWGtgLk6iaWeuHUjz6PzjYgD6bNgqkqk4u6ECWjD2v88R1eRBPw3nNQnG6QMrmofSZcKfmMmJpy"
    private static let content = "c45WurN5j5WeFqxZMB8ZY9p4D2Ks9rNTEmbXFihjWmCJjDM66pNmRYvW41hGt1Bzj8iJ8WsqyXwNmH7VAJSjvwV91v"

    /// name: (target, hard link, own C4 ID or nil)
    private static let expected: [String: (String, Int, String?)] = [
        "id-null": (idText, 0, nil),
        "id-set": (idText, 0, content),
        "id-exr-null": (idText + ".exr", 0, nil),
        "id-exr-set": (idText + ".exr", 0, content),
        "c4-prefix-null": ("c4studio", 0, nil),
        "objects-null": ("../objects/" + idText, 0, nil),
        "hard-null-id": ("", -1, content),
        "hard-null-nil": ("", -1, nil),
        "epoch-link-nil": ("missing.txt", 0, nil),
        "epoch-link-id": ("real.txt", 0, content),
    ]

    private static func check(_ entries: [Entry], form: String) {
        #expect(entries.count == expected.count, "\(form): entry count")
        for e in entries {
            guard let want = expected[e.name] else {
                Issue.record("\(form): unexpected entry \(e.name)")
                continue
            }
            #expect(e.target == want.0, "\(form): \(e.name) target")
            #expect(e.hardLink == want.1, "\(form): \(e.name) hard link")
            #expect(e.c4id?.string == want.2, "\(form): \(e.name) C4 ID")
        }
    }

    @Test("canonical.c4m and pretty.c4m decode to the vector's entries and root ID")
    func plainForms() throws {
        let rootID = try Self.fixture("root-id", "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        for form in ["canonical", "pretty"] {
            let m = try Manifest.unmarshal(try Self.fixture(form, "c4m"))
            Self.check(m.entries, form: form)
            #expect(m.computeC4ID().string == rootID, "\(form): root ID")
        }
    }

    @Test("patch.c4m decodes to the same entries over the empty tree")
    func patchForm() throws {
        let m = try Manifest.unmarshal(try Self.fixture("patch", "c4m"))
        #expect(m.base?.string == Manifest().computeC4ID().string, "patch: base is the empty tree")
        Self.check(m.entries, form: "patch")
    }
}
