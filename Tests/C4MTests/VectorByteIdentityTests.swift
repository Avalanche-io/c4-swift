import Testing
import Foundation
import CryptoKit
@testable import C4M

/// Byte identity over every shared vector this port vendors, as each
/// vector's README states it. Every vector README carries a "## Round trip"
/// table (c4 #158, at 7ac7183), which c4 core's `TestVectorRoundTrip` reads and
/// every port runs: each `.c4m` file is decoded and encoded canonically, and
/// the SHA-512 of the bytes (CryptoKit's, not the port's C4 ID code) is
/// checked against the row. A c4m file's byte ID is a C4 ID, so a round trip
/// that keeps or drops bytes changes it: that is data loss (decided
/// 2026-11-13 by the release lead; reversible).
///
/// A row's second cell is one of:
/// - `itself`: the output is the file, byte for byte;
/// - a backticked file: the output is that file (its canonical partner);
/// - `ID in` a backticked file: a chain whose resolved state has that ID;
/// - `refused`: decoding fails.
///
/// Any other entry fails. Every vendored `.c4m` must be named exactly once. A row naming a file this
/// port does not vendor is passed over.
@Suite("Vector Byte Identity")
struct VectorByteIdentityTests {

    struct Row {
        var file: String  // a name in the directory, or a glob such as */*.c4m
        var want: String  // itself | `NAME` | ID in `NAME` | refused
    }

    private static var root: URL { Bundle.module.resourceURL! }

    /// The vendored vector directories: every resource directory with a README.
    static func vectorDirs() throws -> [String] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(atPath: root.path).filter {
            fm.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("README.md").path)
        }.sorted()
    }

    /// The `.c4m` files under a directory, relative to it.
    static func c4mFiles(_ dir: String) -> [String] {
        let base = root.appendingPathComponent(dir)
        let walk = FileManager.default.enumerator(atPath: base.path)
        var out: [String] = []
        while let p = walk?.nextObject() as? String {
            if p.hasSuffix(".c4m") { out.append(p) }
        }
        return out.sorted()
    }

    /// The rows of the README's "## Round trip" table. The first cell's
    /// backticks are removed; the second keeps its own.
    static func rows(_ dir: String) throws -> [Row] {
        let text = try String(contentsOf: root.appendingPathComponent(dir).appendingPathComponent("README.md"), encoding: .utf8)
        var rows: [Row] = []
        var inTable = false, header = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## ") {
                inTable = line == "## Round trip"
                continue
            }
            guard inTable, line.hasPrefix("|") else { continue }
            if header < 2 { header += 1; continue }  // the header row and its separator
            let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 2 else {
                Issue.record("\(dir)/README.md: a Round trip row needs two cells: \(line)")
                continue
            }
            rows.append(Row(file: cells[0].trimmingCharacters(in: CharacterSet(charactersIn: "`")), want: cells[1]))
        }
        return rows
    }

    /// The name inside the outermost backticks of s.
    static func quoted(_ s: String) -> String {
        guard let i = s.firstIndex(of: "`"), let j = s.lastIndex(of: "`"), i < j else { return "" }
        return String(s[s.index(after: i)..<j])
    }

    static func matches(_ pattern: String, _ path: String) -> Bool {
        fnmatch(pattern, path, FNM_PATHNAME) == 0
    }

    @Test("every vendored .c4m is named exactly once in its README's Round trip table",
          arguments: try vectorDirs())
    func coverage(dir: String) throws {
        let files = Self.c4mFiles(dir)
        let rows = try Self.rows(dir)
        if files.isEmpty {
            #expect(rows.isEmpty, "\(dir): a Round trip table, but no .c4m files")
            return
        }
        #expect(!rows.isEmpty, "\(dir): \(files.count) .c4m files and no Round trip table")
        for f in files {
            let n = rows.filter { Self.matches($0.file, f) }.count
            #expect(n == 1, "\(dir)/\(f): named \(n) times in its README's Round trip table, want once")
        }
    }

    @Test("decode and canonical re-encode, checked against the README's Round trip table by SHA-512",
          arguments: try vectorDirs())
    func roundTrip(dir: String) throws {
        let files = Self.c4mFiles(dir)
        for row in try Self.rows(dir) {
            for f in files where Self.matches(row.file, f) {
                try Self.check(dir: dir, file: f, want: row.want)
            }
        }
    }

    static func read(_ dir: String, _ file: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(dir).appendingPathComponent(file))
    }

    static func check(dir: String, file: String, want: String) throws {
        let path = "\(dir)/\(file)"
        let input = try read(dir, file)
        let decoded = Result { try Manifest.unmarshal(input) }
        if want == "refused" {
            if case .success = decoded { Issue.record("\(path): decoded, but its README says it is refused") }
            return
        }
        let m: Manifest
        switch decoded {
        case .success(let v): m = v
        case .failure(let e):
            if want == "itself", try utf8Exempt(dir: dir, error: e) {
                try checkUTF8Rest(path: path, input: input)
                return
            }
            Issue.record("\(path): \(e)")
            return
        }
        let output = Data(try m.marshal().utf8)
        if want == "itself" {
            #expect(SHA512.hash(data: output) == SHA512.hash(data: input), "\(path) does not re-encode to itself")
        } else if want.hasPrefix("ID in ") {
            let id = String(decoding: try read(dir, quoted(want)), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(m.computeC4ID().string == id, "\(path) resolves to \(m.computeC4ID().string), want \(id) (\(quoted(want)))")
        } else if !quoted(want).isEmpty && quoted(want) == want.trimmingCharacters(in: CharacterSet(charactersIn: "`")) {
            let partner = try read(dir, quoted(want))
            #expect(SHA512.hash(data: output) == SHA512.hash(data: partner), "\(path) does not re-encode to \(quoted(want))")
        } else {
            Issue.record("\(path): unknown Round trip entry \(want)")
        }
    }

    /// The one place the table's Go round trip does not bind this port, and
    /// only while the vector's own README says so. SafeNameVector's README,
    /// decided 2026-11-13 by the release lead (reversible): "Names that are
    /// not valid UTF-8 are refused, naming the line, by implementations whose
    /// string type cannot hold them (c4ts, c4m-swift), for 1.x." A Swift
    /// String cannot hold them, so such a file is refused at that line.
    static let utf8Exemption = "refused, naming the line, by implementations whose string type cannot hold them (c4ts, c4m-swift)"

    static func utf8Exempt(dir: String, error: Error) throws -> Bool {
        let readme = try String(contentsOf: root.appendingPathComponent(dir).appendingPathComponent("README.md"), encoding: .utf8)
        let flat = readme.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.contains(utf8Exemption), case C4MError.invalidEntry(_, let why) = error else { return false }
        return why.contains("not UTF-8")
    }

    /// An exempt file still owes byte identity on every line it can hold:
    /// less the lines refused alone (each one must be refused for not being
    /// UTF-8), the rest of a flat file re-encodes to itself byte for byte.
    static func checkUTF8Rest(path: String, input: Data) throws {
        let lines = String(decoding: input, as: UTF8.self).split(separator: "\n")
        #expect(!lines.contains { $0.hasPrefix(" ") }, "\(path): the exemption applies only to a flat file")
        var kept: [Substring] = []
        var refused = 0
        for l in lines {
            do {
                _ = try Manifest.unmarshal(String(l) + "\n")
                kept.append(l)
            } catch C4MError.invalidEntry(_, let why) where why.contains("not UTF-8") {
                refused += 1
            }
        }
        #expect(refused > 0, "\(path): refused, but no single line is refused for not being UTF-8")
        let rest = Data((kept.joined(separator: "\n") + "\n").utf8)
        let output = Data(try Manifest.unmarshal(rest).marshal().utf8)
        #expect(SHA512.hash(data: output) == SHA512.hash(data: rest), "\(path), less its \(refused) names that are not UTF-8, does not re-encode to itself")
    }
}
