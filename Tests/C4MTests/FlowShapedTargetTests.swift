import Testing
import Foundation
@testable import C4M

/// A symlink whose target has the shape of a flow target (`host:path`,
/// `C:foo`) cannot be told from a flow link when the mode is null. Ruled
/// 2026-11-13 (decided by the release lead; reversible; LinkTargetVector
/// README, "A flow-shaped target under a null mode"): under a null mode `-`
/// the line is a flow link, and under `lrwxrwxrwx` it is the symlink. A
/// port of c4 core's `TestAFlowShapedTargetIsALinkOnlyUnderASymlinkMode`.
@Suite("Flow-shaped Link Targets")
struct FlowShapedTargetTests {
    static let targets = ["host:path", "C:foo", "studio:inbox/"]
    static let content = C4ID.identify(string: "what the link points at")

    @Test("the link's content ID is the one core writes")
    func contentID() {
        #expect(Self.content.string == "c45WurN5j5WeFqxZMB8ZY9p4D2Ks9rNTEmbXFihjWmCJjDM66pNmRYvW41hGt1Bzj8iJ8WsqyXwNmH7VAJSjvwV91v")
    }

    /// The lines c4 core writes for these entries (measured on c4 7cdc9f3).
    @Test("core's lines read as a symlink under lrwxrwxrwx and as a flow link under -",
          arguments: targets, [false, true])
    func coreLines(target: String, withID: Bool) throws {
        let id = withID ? Self.content.string : "-"
        let link = try Manifest.unmarshal("lrwxrwxrwx - - link -> \(target) \(id)\n").entries[0]
        #expect(link.isSymlink && link.target == target && link.flowDirection == .none)
        let flow = try Manifest.unmarshal("- - - link -> \(target) \(id)\n").entries[0]
        #expect(!flow.isSymlink && flow.target == "" && flow.flowDirection == .outbound && flow.flowTarget == target)
    }

    /// The same entries written by this port are core's lines, byte for
    /// byte, and read back the same way.
    @Test("an entry written under each mode is core's line and reads back under the ruling", arguments: targets, [false, true])
    func roundTrip(target: String, withID: Bool) throws {
        let id: C4ID? = withID ? Self.content : nil
        let idField = withID ? Self.content.string : "-"
        var m = Manifest()
        m.addEntry(Entry(mode: .symlink777, timestamp: Entry.nullTimestamp, size: -1, name: "link", target: target, c4id: id))
        #expect(try m.marshal() == "lrwxrwxrwx - - link -> \(target) \(idField)\n")
        let link = try Manifest.unmarshal(try m.marshal()).entries[0]
        #expect(link.isSymlink && link.target == target && link.flowDirection == .none)

        m = Manifest()
        m.addEntry(Entry(mode: .null, timestamp: Entry.nullTimestamp, size: -1, name: "link", target: target, c4id: id))
        #expect(try m.marshal() == "- - - link -> \(target) \(idField)\n")
        let flow = try Manifest.unmarshal(try m.marshal()).entries[0]
        #expect(flow.flowDirection == .outbound && flow.flowTarget == target && flow.target == "")
    }
}
