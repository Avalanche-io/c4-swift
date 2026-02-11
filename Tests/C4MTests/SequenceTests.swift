import Testing
import Foundation
@testable import C4M

@Suite("Sequence Tests")
struct SequenceTests {

    @Test("Parse simple range")
    func parseSimpleRange() throws {
        let seq = try Sequence.parse("frame.[0001-0100].exr")
        #expect(seq.prefix == "frame.")
        #expect(seq.suffix == ".exr")
        #expect(seq.padding == 4)
        #expect(seq.ranges.count == 1)
        #expect(seq.ranges[0].start == 1)
        #expect(seq.ranges[0].end == 100)
        #expect(seq.ranges[0].step == 1)
    }

    @Test("Parse stepped range")
    func parseSteppedRange() throws {
        let seq = try Sequence.parse("render.[0001-0100:2].png")
        #expect(seq.ranges[0].step == 2)
    }

    @Test("Parse multiple ranges")
    func parseMultipleRanges() throws {
        let seq = try Sequence.parse("shot.[01-50,75-100].dpx")
        #expect(seq.ranges.count == 2)
        #expect(seq.ranges[0].start == 1)
        #expect(seq.ranges[0].end == 50)
        #expect(seq.ranges[1].start == 75)
        #expect(seq.ranges[1].end == 100)
    }

    @Test("Parse individual frames")
    func parseIndividual() throws {
        let seq = try Sequence.parse("frame.[001,005,010,015].exr")
        #expect(seq.ranges.count == 4)
        #expect(seq.ranges[0].start == 1)
        #expect(seq.ranges[0].end == 1)
    }

    @Test("Parse space in filename")
    func parseSpaceInFilename() throws {
        let seq = try Sequence.parse("my\\ animation.[001-100].png")
        #expect(seq.prefix == "my animation.")
    }

    @Test("Invalid: no pattern")
    func invalidNoPattern() {
        #expect(throws: C4MError.self) {
            try Sequence.parse("regular_file.txt")
        }
    }

    @Test("Invalid: start > end")
    func invalidReversedRange() {
        #expect(throws: C4MError.self) {
            try Sequence.parse("frame.[100-1].exr")
        }
    }

    @Test("Expand simple range")
    func expandSimple() throws {
        let seq = try Sequence.parse("frame.[0001-0003].exr")
        let files = seq.expand()
        #expect(files == ["frame.0001.exr", "frame.0002.exr", "frame.0003.exr"])
    }

    @Test("Expand stepped range")
    func expandStepped() throws {
        let seq = try Sequence.parse("render.[001-010:3].png")
        let files = seq.expand()
        #expect(files == ["render.001.png", "render.004.png", "render.007.png", "render.010.png"])
    }

    @Test("Expand multiple ranges")
    func expandMultiple() throws {
        let seq = try Sequence.parse("shot.[01-02,05-06].dpx")
        let files = seq.expand()
        #expect(files == ["shot.01.dpx", "shot.02.dpx", "shot.05.dpx", "shot.06.dpx"])
    }

    @Test("Count simple range")
    func countSimple() throws {
        let seq = try Sequence.parse("frame.[0001-0100].exr")
        #expect(seq.count == 100)
    }

    @Test("Count stepped range")
    func countStepped() throws {
        let seq = try Sequence.parse("frame.[0001-0100:2].exr")
        #expect(seq.count == 50)
    }

    @Test("Count multiple ranges")
    func countMultiple() throws {
        let seq = try Sequence.parse("shot.[01-50,75-100].dpx")
        #expect(seq.count == 76)
    }

    @Test("Contains check")
    func containsCheck() throws {
        let seq = Sequence(
            prefix: "f.", suffix: ".exr",
            ranges: [
                SequenceRange(start: 1, end: 10, step: 1),
                SequenceRange(start: 20, end: 30, step: 2),
            ],
            padding: 4
        )
        #expect(seq.contains(frame: 1))
        #expect(seq.contains(frame: 5))
        #expect(seq.contains(frame: 10))
        #expect(!seq.contains(frame: 11))
        #expect(seq.contains(frame: 20))
        #expect(!seq.contains(frame: 21))
        #expect(seq.contains(frame: 22))
        #expect(seq.contains(frame: 30))
        #expect(!seq.contains(frame: 31))
    }

    @Test("Detect sequences in manifest")
    func detectInManifest() {
        var manifest = Manifest()
        for i in 1 ... 10 {
            manifest.addEntry(Entry(
                mode: .file644,
                timestamp: Date(),
                size: 1024,
                name: String(format: "frame.%04d.exr", i)
            ))
        }
        manifest.addEntry(Entry(mode: .file644, size: 100, name: "readme.txt"))

        let result = detectSequences(in: manifest)
        #expect(result.entries.count == 2) // 1 sequence + 1 file

        let seqEntry = result.entries.first { $0.isSequence }
        #expect(seqEntry != nil)
        #expect(seqEntry?.pattern == "frame.[0001-0010].exr")
    }

    @Test("Detect sequences respects minLength")
    func detectMinLength() {
        var manifest = Manifest()
        for i in 1 ... 2 {
            manifest.addEntry(Entry(
                mode: .file644,
                size: 512,
                name: String(format: "clip.%04d.dpx", i)
            ))
        }

        // Default minLength is 3, so 2 files should not collapse
        let result = detectSequences(in: manifest)
        #expect(result.entries.count == 2)
        #expect(result.entries.allSatisfy { !$0.isSequence })
    }

    @Test("ExpandSequencePattern convenience")
    func expandConvenience() throws {
        let files = try expandSequencePattern("frame.[01-03].exr")
        #expect(files == ["frame.01.exr", "frame.02.exr", "frame.03.exr"])
    }
}
