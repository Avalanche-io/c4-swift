import Testing
@testable import C4M

@Suite("Natural Sort Tests")
struct NaturalSortTests {

    @Test("Basic numeric sorting")
    func basicNumeric() {
        var input = ["file10.txt", "file2.txt", "file1.txt"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["file1.txt", "file2.txt", "file10.txt"])
    }

    @Test("Multiple numeric sequences")
    func multipleNumeric() {
        var input = ["a10b20", "a2b3", "a10b3", "a2b20"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["a2b3", "a2b20", "a10b3", "a10b20"])
    }

    @Test("Leading zeros")
    func leadingZeros() {
        var input = ["file001.txt", "file010.txt", "file100.txt", "file002.txt"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["file001.txt", "file002.txt", "file010.txt", "file100.txt"])
    }

    @Test("No numbers")
    func noNumbers() {
        var input = ["zebra", "apple", "banana"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["apple", "banana", "zebra"])
    }

    @Test("Version numbers")
    func versionNumbers() {
        var input = ["v1.10.2", "v1.2.1", "v1.10.10", "v1.2.10"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["v1.2.1", "v1.2.10", "v1.10.2", "v1.10.10"])
    }

    @Test("Frame sequences")
    func frameSequences() {
        var input = ["frame.0100.exr", "frame.0010.exr", "frame.0001.exr", "frame.1000.exr"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["frame.0001.exr", "frame.0010.exr", "frame.0100.exr", "frame.1000.exr"])
    }

    @Test("Empty strings")
    func emptyStrings() {
        var input = ["", "a", "", "b"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["", "", "a", "b"])
    }

    @Test("Hidden files")
    func hiddenFiles() {
        var input = [".file10", ".file2", "file1", ".file1"]
        input.sort { naturalLess($0, $1) }
        #expect(input == [".file1", ".file2", ".file10", "file1"])
    }

    @Test("Case sensitivity")
    func caseSensitivity() {
        var input = ["File10.txt", "file2.txt", "FILE1.txt"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["FILE1.txt", "File10.txt", "file2.txt"])
    }

    @Test("Unicode")
    func unicode() {
        var input = ["文件10.txt", "文件2.txt", "文件1.txt"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["文件1.txt", "文件2.txt", "文件10.txt"])
    }

    @Test("Same prefix different extensions")
    func samePrefix() {
        var input = ["file.zip", "file.txt", "file.doc"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["file.doc", "file.txt", "file.zip"])
    }

    @Test("Numbers at start")
    func numbersAtStart() {
        var input = ["10file.txt", "2file.txt", "1file.txt"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["1file.txt", "2file.txt", "10file.txt"])
    }

    @Test("NaturalLess direct comparison")
    func directComparison() {
        #expect(naturalLess("file1.txt", "file10.txt"))
        #expect(!naturalLess("file10.txt", "file1.txt"))
        #expect(!naturalLess("file2.txt", "file2.txt"))
    }

    @Test("Leading zeros: shorter representation first")
    func leadingZerosShorterFirst() {
        // Equal value, shorter representation first: "1" < "001"
        #expect(naturalLess("file1.txt", "file001.txt"))
        #expect(!naturalLess("file001.txt", "file1.txt"))
    }

    @Test("Identical strings are not less")
    func identicalNotLess() {
        #expect(!naturalLess("file.txt", "file.txt"))
    }

    @Test("Paths with natural sort")
    func pathsSort() {
        var input = ["dir10/file2.txt", "dir2/file10.txt", "dir2/file2.txt", "dir10/file10.txt"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["dir2/file2.txt", "dir2/file10.txt", "dir10/file2.txt", "dir10/file10.txt"])
    }

    @Test("Decimal numbers")
    func decimalNumbers() {
        var input = ["file1.5.txt", "file1.10.txt", "file1.2.txt"]
        input.sort { naturalLess($0, $1) }
        #expect(input == ["file1.2.txt", "file1.5.txt", "file1.10.txt"])
    }
}
