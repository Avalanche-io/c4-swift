import Testing
import Foundation
@testable import C4M

/// A size of 0 beside a C4 ID other than the empty content's is a null size
/// (c4 #68; ruled 2026-11-08, decided 2026-11-13 by the release lead;
/// reversible). `Entry.sizeIsNull` is the one test; these pin every place
/// it is applied. The shared fixture is in NullSizeVectorTests.
@Suite("A size of 0 beside a C4 ID is a null size")
struct NullSizeZeroTests {

    static let ts = "2026-03-06T12:00:00Z"
    static let hello = C4ID.identify(string: "hello")
    static let empty = Entry.emptyContentID

    @Test("emptyContentID is the C4 ID of zero bytes")
    func emptyContentID() {
        #expect(Entry.emptyContentID == C4ID.identify(data: Data()))
        #expect(Entry.emptyContentID.string ==
            "c459dsjfscH38cYeXXYogktxf4Cd9ibshE3BHUo6a58hBXmRQdZrAkZzsWcbWtDg5oQstpDuni4Hirj75GEmTc1sFT")
    }

    /// The same table as c4 core's TestNullSizeZero.
    @Test("decoded lines", arguments: [
        ("-rw-r--r-- \(ts) 0 f \(hello.string)", true),
        ("-rw-r--r-- \(ts) 0 f \(empty.string)", false),
        ("-rw-r--r-- \(ts) 0 f -", false),
        ("lrwxr-xr-x \(ts) 0 l -> f \(hello.string)", false),
        ("drwxr-xr-x \(ts) 0 d/ \(empty.string)", false),
        ("drwxr-xr-x \(ts) 0 d/ \(hello.string)", true),
        ("-rw-r--r-- \(ts) 5 f \(hello.string)", false),
        ("-rw-r--r-- \(ts) - f \(hello.string)", true),
    ])
    func decodedLine(line: String, wantNull: Bool) throws {
        let e = try #require(try Manifest.unmarshal(line + "\n").entries.first)
        #expect(e.sizeIsNull == wantNull)
        if wantNull {
            #expect(e.size == -1, "the decoder holds a null size as -1")
        } else if e.size != 5 {
            #expect(e.size == 0, "a known zero stays 0")
        }
        let size = e.canonical.split(separator: " ")[2]
        #expect((size == "-") == wantNull, "canonical size field \(size)")
    }

    @Test("0 and - beside a real content ID are one description, however built")
    func oneID() throws {
        let fromZero = try Manifest.unmarshal("-rw-r--r-- \(Self.ts) 0 f \(Self.hello.string)\n")
        let fromDash = try Manifest.unmarshal("-rw-r--r-- \(Self.ts) - f \(Self.hello.string)\n")
        #expect(fromZero.computeC4ID() == fromDash.computeC4ID())

        // Built through the API with size 0 (as a scan over a mount would
        // build it), the entry still renders and hashes as null.
        let e = Entry(mode: .file644, timestamp: fromDash.entries[0].timestamp, size: 0, name: "f", c4id: Self.hello)
        let built = Manifest(entries: [e])
        #expect(built.computeC4ID() == fromDash.computeC4ID())
        #expect(try built.marshal().contains(" - f "))
        #expect(try built.marshalPretty().contains(" - f "))
        #expect(e.format().contains(" - f "))
        #expect(e.hasNullValues)
    }

    @Test("a null written as 0 makes its parent directory's size null")
    func propagates() throws {
        var m = try Manifest.unmarshal(
            "drwxr-xr-x \(Self.ts) - d/ -\n" +
            "  -rw-r--r-- \(Self.ts) 0 f \(Self.hello.string)\n")
        m.canonicalize()
        let d = try #require(m.entries.first { $0.name == "d/" })
        #expect(d.sizeIsNull, "decoded: directory size over a null child")

        // The same through the API: a child built with 0 beside a real ID
        // (never held as -1) still makes the parent's size null.
        var built = Manifest(entries: [
            Entry(mode: .dir755, size: -1, name: "d/"),
            Entry(mode: .file644, size: 0, name: "f", c4id: Self.hello, depth: 1),
        ])
        built.canonicalize()
        let bd = try #require(built.entries.first { $0.name == "d/" })
        #expect(bd.sizeIsNull, "built: directory size over a null child")
    }
}
