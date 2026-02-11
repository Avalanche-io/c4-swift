import Foundation

/// Errors that can occur during C4M parsing.
public enum C4MError: Error, Sendable, CustomStringConvertible {
    case invalidHeader(String)
    case unsupportedVersion(String)
    case invalidEntry(Int, String)
    case duplicatePath(String)
    case pathTraversal(String)
    case notSupported(String)

    public var description: String {
        switch self {
        case .invalidHeader(let msg): return "c4m: invalid header: \(msg)"
        case .unsupportedVersion(let v): return "c4m: unsupported version: \(v)"
        case .invalidEntry(let line, let msg): return "c4m: line \(line): \(msg)"
        case .duplicatePath(let p): return "c4m: duplicate path: \(p)"
        case .pathTraversal(let p): return "c4m: path traversal: \(p)"
        case .notSupported(let f): return "c4m: not supported: \(f)"
        }
    }
}

/// Character-level parser for the C4M text format.
public struct Decoder: Sendable {

    private let input: String
    private var lines: [Substring]
    private var lineIndex: Int = 0
    private var indentWidth: Int = -1
    private var version: String = ""

    /// Create a decoder from a string.
    public init(string: String) {
        self.input = string
        self.lines = string.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Create a decoder from UTF-8 data.
    public init(data: Data) {
        self.init(string: String(data: data, encoding: .utf8) ?? "")
    }

    /// Decode the input into a Manifest.
    public mutating func decode() throws -> Manifest {
        try parseHeader()

        var manifest = Manifest(version: version)
        var currentLayer: Int? = nil

        while lineIndex < lines.count {
            let line = String(lines[lineIndex])
            lineIndex += 1

            if line.isEmpty { continue }

            if line.hasPrefix("@") {
                try handleDirective(line, manifest: &manifest, currentLayer: &currentLayer)
                continue
            }

            let entry = try parseEntryLine(line)
            manifest.entries.append(entry)
        }

        return manifest
    }

    // MARK: - Header

    private mutating func parseHeader() throws {
        guard lineIndex < lines.count else {
            throw C4MError.invalidHeader("empty input")
        }
        let line = String(lines[lineIndex])
        lineIndex += 1

        guard line.hasPrefix("@c4m ") else {
            throw C4MError.invalidHeader("expected '@c4m X.Y', got '\(line)'")
        }

        let v = String(line.dropFirst(5))
        guard !v.isEmpty else {
            throw C4MError.invalidHeader("missing version number")
        }
        guard v.hasPrefix("1.") else {
            throw C4MError.unsupportedVersion(v)
        }
        version = v
    }

    // MARK: - Entry Parsing

    private mutating func parseEntryLine(_ line: String) throws -> Entry {
        let lineNum = lineIndex // already incremented

        // Detect indentation
        var indent = 0
        for ch in line {
            if ch == " " { indent += 1 } else { break }
        }
        if indentWidth == -1 && indent > 0 { indentWidth = indent }
        let depth = indentWidth > 0 ? indent / indentWidth : 0

        let trimmed = String(line.drop(while: { $0 == " " }))

        // Parse mode
        var modeStr: String
        var rest: String
        if trimmed.hasPrefix("- ") {
            modeStr = "-"
            rest = String(trimmed.dropFirst(2))
        } else if trimmed.count >= 11 {
            modeStr = String(trimmed.prefix(10))
            rest = String(trimmed.dropFirst(11))
        } else {
            throw C4MError.invalidEntry(lineNum, "line too short")
        }

        let mode = FileMode(string: modeStr)
        // nil mode means unspecified/null (value 0)

        // Parse timestamp
        var timestamp: Date
        if rest.hasPrefix("- ") || rest.hasPrefix("0 ") {
            timestamp = Date(timeIntervalSince1970: 0)
            rest = String(rest.dropFirst(2))
        } else if rest.count >= 20 && rest[rest.index(rest.startIndex, offsetBy: 4)] == "-" &&
                    rest[rest.index(rest.startIndex, offsetBy: 10)] == "T" {
            // ISO 8601 format
            var endIdx = 20
            if rest.count >= 25 {
                let char19 = rest[rest.index(rest.startIndex, offsetBy: 19)]
                if char19 == "-" || char19 == "+" { endIdx = 25 }
            }
            let tsStr = String(rest.prefix(endIdx))
            guard let ts = Decoder.parseTimestamp(tsStr) else {
                throw C4MError.invalidEntry(lineNum, "invalid timestamp '\(tsStr)'")
            }
            timestamp = ts
            rest = endIdx < rest.count ? String(rest.dropFirst(endIdx + 1)) : ""
        } else {
            // Try pretty format (Mon Day Time Year TZ)
            let parts = rest.split(separator: " ", omittingEmptySubsequences: false)
            let nonEmpty = parts.filter { !$0.isEmpty }
            if nonEmpty.count >= 5 {
                let tsStr = nonEmpty[0 ..< 5].joined(separator: " ")
                guard let ts = Decoder.parseTimestamp(tsStr) else {
                    throw C4MError.invalidEntry(lineNum, "cannot parse timestamp from '\(tsStr)'")
                }
                timestamp = ts
                rest = nonEmpty[5...].joined(separator: " ")
            } else {
                throw C4MError.invalidEntry(lineNum, "cannot parse timestamp")
            }
        }

        // Parse remaining: size name [-> target] [c4id]
        let (size, name, target, c4id) = try parseEntryFields(rest, lineNum: lineNum)

        var entry = Entry(
            mode: mode ?? .null,
            timestamp: timestamp,
            size: size,
            name: name,
            target: target,
            c4id: c4id,
            depth: depth
        )

        // Detect sequence notation
        if name.contains("[") && name.contains("]") {
            entry.isSequence = true
            entry.pattern = name
        }

        return entry
    }

    /// Parse "size name [-> target] [c4id]" using character-level scanning.
    private func parseEntryFields(_ line: String, lineNum: Int) throws -> (Int64, String, String, C4ID) {
        let chars = Array(line.utf8)
        var pos = 0
        let n = chars.count

        // Skip leading whitespace
        while pos < n && chars[pos] == 0x20 { pos += 1 }
        guard pos < n else { throw C4MError.invalidEntry(lineNum, "missing fields after timestamp") }

        // 1. Parse size
        let sizeStart = pos
        var size: Int64
        if chars[pos] == 0x2D { // '-'
            size = -1
            pos += 1
        } else {
            while pos < n && ((chars[pos] >= 0x30 && chars[pos] <= 0x39) || chars[pos] == 0x2C) {
                pos += 1
            }
            guard pos > sizeStart else {
                throw C4MError.invalidEntry(lineNum, "invalid size")
            }
            let sizeStr = String(line[line.index(line.startIndex, offsetBy: sizeStart) ..< line.index(line.startIndex, offsetBy: pos)])
                .replacingOccurrences(of: ",", with: "")
            guard let s = Int64(sizeStr) else {
                throw C4MError.invalidEntry(lineNum, "invalid size '\(sizeStr)'")
            }
            size = s
        }

        // Skip whitespace
        while pos < n && chars[pos] == 0x20 { pos += 1 }
        guard pos < n else { throw C4MError.invalidEntry(lineNum, "missing name after size") }

        // 2. Parse name (quoted or unquoted)
        let (name, nameEnd) = try parseName(line, from: pos, lineNum: lineNum)
        pos = nameEnd

        // Skip whitespace
        while pos < n && chars[pos] == 0x20 { pos += 1 }

        // 3. Check for symlink "->"
        var target = ""
        if pos + 1 < n && chars[pos] == 0x2D && chars[pos + 1] == 0x3E { // '->'
            pos += 2
            while pos < n && chars[pos] == 0x20 { pos += 1 }
            let (t, tEnd) = try parseTargetField(line, from: pos, lineNum: lineNum)
            target = t
            pos = tEnd
            while pos < n && chars[pos] == 0x20 { pos += 1 }
        }

        // 4. Parse optional C4 ID
        var c4id = C4ID.void
        if pos < n {
            let remaining = String(line[line.index(line.startIndex, offsetBy: pos)...]).trimmingCharacters(in: .whitespaces)
            if remaining == "-" {
                c4id = .void
            } else if remaining.hasPrefix("c4"), let parsed = C4ID(remaining) {
                c4id = parsed
            }
        }

        return (size, name, target, c4id)
    }

    /// Parse a quoted or unquoted name starting at `from`.
    private func parseName(_ line: String, from: Int, lineNum: Int) throws -> (String, Int) {
        let chars = Array(line.utf8)
        let n = chars.count
        var pos = from
        guard pos < n else { throw C4MError.invalidEntry(lineNum, "unexpected end of line") }

        if chars[pos] == 0x22 { // '"'
            return try parseQuoted(line, from: pos, lineNum: lineNum)
        }

        // Unquoted name: scan for boundary
        let start = pos
        while pos < n {
            let ch = chars[pos]

            // Directory name ends at '/' (inclusive)
            if ch == 0x2F { // '/'
                pos += 1
                return (String(line[line.index(line.startIndex, offsetBy: start) ..< line.index(line.startIndex, offsetBy: pos)]), pos)
            }

            // Boundary: space followed by "->", "c4", or "-" (null c4id)
            if ch == 0x20 {
                let restStart = pos
                let restCount = n - restStart
                if restCount >= 4 {
                    let r1 = chars[restStart + 1]
                    let r2 = chars[restStart + 2]
                    let r3 = chars[restStart + 3]
                    // " -> "
                    if r1 == 0x2D && r2 == 0x3E && r3 == 0x20 {
                        return (String(line[line.index(line.startIndex, offsetBy: start) ..< line.index(line.startIndex, offsetBy: pos)]), pos)
                    }
                    // " c4"
                    if r1 == 0x63 && r2 == 0x34 { // 'c', '4'
                        return (String(line[line.index(line.startIndex, offsetBy: start) ..< line.index(line.startIndex, offsetBy: pos)]), pos)
                    }
                }
                if restCount >= 2 {
                    let r1 = chars[restStart + 1]
                    // " -" followed by end or space (null C4 ID)
                    if r1 == 0x2D && (restCount == 2 || chars[restStart + 2] == 0x20) {
                        return (String(line[line.index(line.startIndex, offsetBy: start) ..< line.index(line.startIndex, offsetBy: pos)]), pos)
                    }
                }
            }
            pos += 1
        }

        return (String(line[line.index(line.startIndex, offsetBy: start) ..< line.index(line.startIndex, offsetBy: pos)]), pos)
    }

    /// Parse a symlink target starting at `from`. Unlike names, "/" is not a boundary.
    private func parseTargetField(_ line: String, from: Int, lineNum: Int) throws -> (String, Int) {
        let chars = Array(line.utf8)
        let n = chars.count
        var pos = from
        guard pos < n else { throw C4MError.invalidEntry(lineNum, "missing symlink target") }

        if chars[pos] == 0x22 { // '"'
            return try parseQuoted(line, from: pos, lineNum: lineNum)
        }

        // Unquoted target: scan until c4 prefix or end
        let start = pos
        while pos < n {
            if chars[pos] == 0x20 { // space
                let restCount = n - pos
                if restCount > 2 && chars[pos + 1] == 0x63 && chars[pos + 2] == 0x34 { // " c4"
                    return (String(line[line.index(line.startIndex, offsetBy: start) ..< line.index(line.startIndex, offsetBy: pos)]), pos)
                }
                if restCount >= 2 && chars[pos + 1] == 0x2D && (restCount == 2 || chars[pos + 2] == 0x20) {
                    return (String(line[line.index(line.startIndex, offsetBy: start) ..< line.index(line.startIndex, offsetBy: pos)]), pos)
                }
            }
            pos += 1
        }

        return (String(line[line.index(line.startIndex, offsetBy: start)...]), pos)
    }

    /// Parse a quoted string with escape sequences starting at the opening quote.
    private func parseQuoted(_ line: String, from: Int, lineNum: Int) throws -> (String, Int) {
        let chars = Array(line.utf8)
        let n = chars.count
        var pos = from + 1 // skip opening quote
        var buf = ""

        while pos < n {
            let ch = chars[pos]
            if ch == 0x5C && pos + 1 < n { // backslash
                let next = chars[pos + 1]
                switch next {
                case 0x5C: buf.append("\\")
                case 0x22: buf.append("\"")
                case 0x6E: buf.append("\n")
                default:
                    buf.append("\\")
                    buf.append(Character(UnicodeScalar(next)))
                }
                pos += 2
            } else if ch == 0x22 { // closing quote
                pos += 1
                return (buf, pos)
            } else {
                buf.append(Character(UnicodeScalar(ch)))
                pos += 1
            }
        }

        throw C4MError.invalidEntry(lineNum, "unterminated quoted string")
    }

    // MARK: - Directives

    private func handleDirective(_ line: String, manifest: inout Manifest, currentLayer: inout Int?) throws {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let directive = parts.first else { return }

        switch directive {
        case "@base":
            guard parts.count >= 2, let id = C4ID(String(parts[1])) else {
                throw C4MError.invalidEntry(lineIndex, "@base requires valid C4 ID")
            }
            manifest.base = id

        case "@layer":
            let layer = Layer(type: .add)
            manifest.layers.append(layer)
            currentLayer = manifest.layers.count - 1

        case "@remove":
            let layer = Layer(type: .remove)
            manifest.layers.append(layer)
            currentLayer = manifest.layers.count - 1

        case "@by":
            if let idx = currentLayer {
                manifest.layers[idx].by = parts.dropFirst().joined(separator: " ")
            }

        case "@time":
            if let idx = currentLayer, parts.count > 1, let t = Decoder.parseTimestamp(String(parts[1])) {
                manifest.layers[idx].time = t
            }

        case "@note":
            if let idx = currentLayer {
                manifest.layers[idx].note = parts.dropFirst().joined(separator: " ")
            }

        case "@data":
            if parts.count >= 2, let id = C4ID(String(parts[1])) {
                if let idx = currentLayer {
                    manifest.layers[idx].data = id
                } else {
                    manifest.data = id
                }
            }

        case "@end":
            currentLayer = nil

        case "@expand":
            throw C4MError.notSupported("@expand directive")

        default:
            break // Unknown directives are silently ignored
        }
    }

    // MARK: - Timestamp Parsing

    /// Parse a timestamp string in various accepted formats.
    static func parseTimestamp(_ s: String) -> Date? {
        // Canonical: 2006-01-02T15:04:05Z
        let canonical = ISO8601DateFormatter()
        canonical.formatOptions = [.withInternetDateTime]
        canonical.timeZone = TimeZone(identifier: "UTC")
        if let d = canonical.date(from: s) { return d }

        // RFC3339 with offset: 2006-01-02T15:04:05-07:00
        let rfc3339 = ISO8601DateFormatter()
        rfc3339.formatOptions = [.withInternetDateTime]
        if let d = rfc3339.date(from: s) { return d }

        // Pretty format: "Jan  2 15:04:05 2006 MST"
        let pretty = DateFormatter()
        pretty.locale = Locale(identifier: "en_US_POSIX")
        for fmt in [
            "MMM d HH:mm:ss yyyy zzz",
            "MMM  d HH:mm:ss yyyy zzz",
            "MMM d HH:mm:ss yyyy Z",
            "MMM  d HH:mm:ss yyyy Z",
            "EEE MMM d HH:mm:ss zzz yyyy",
            "EEE MMM  d HH:mm:ss zzz yyyy",
        ] {
            pretty.dateFormat = fmt
            if let d = pretty.date(from: s) { return d }
        }

        return nil
    }
}

// MARK: - Convenience

extension Manifest {
    /// Parse a C4M string.
    public static func unmarshal(_ string: String) throws -> Manifest {
        var decoder = Decoder(string: string)
        return try decoder.decode()
    }

    /// Parse C4M data.
    public static func unmarshal(_ data: Data) throws -> Manifest {
        var decoder = Decoder(data: data)
        return try decoder.decode()
    }
}
