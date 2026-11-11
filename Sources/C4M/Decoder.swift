import Foundation

/// Character-level parser for the C4M text format.
/// Entry-only format: no header, no directives. Lines starting with @ are rejected.
public struct Decoder: Sendable {

    private let input: String
    private var lines: [Substring]
    private var lineIndex: Int = 0
    private var indentWidth: Int = -1

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
    /// Entry-only format with patch boundary support:
    /// - First bare C4 ID (before entries) = external base reference
    /// - Subsequent bare C4 IDs = inline checkpoints (must match accumulated state)
    public mutating func decode() throws -> Manifest {
        var manifest = Manifest()
        var section: [Entry] = []
        var firstLine = true
        var patchMode = false
        var externalBase = false

        while lineIndex < lines.count {
            let line = String(lines[lineIndex])
            lineIndex += 1

            // Reject CR characters (check raw bytes — Swift's String treats \r\n as a single grapheme)
            if line.utf8.contains(0x0D) {
                throw C4MError.invalidEntry(lineIndex, "CR (0x0D) not allowed — c4m requires LF-only line endings")
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip blank lines
            if trimmed.isEmpty { continue }

            // Check for inline ID list (>90 chars, multiple of 90, all valid C4 IDs)
            if Decoder.isInlineIDList(trimmed) {
                let id = C4ID.identify(string: trimmed)
                manifest.rangeData[id] = trimmed
                continue
            }

            // Check for bare C4 ID line (exactly 90 chars starting with "c4")
            if Decoder.isBareC4ID(trimmed) {
                guard let id = C4ID(trimmed) else {
                    throw C4MError.invalidEntry(lineIndex, "invalid C4 ID")
                }

                if firstLine && section.isEmpty {
                    // First non-blank line: external base reference. There is
                    // no accumulated content to verify against — the consumer
                    // must fetch the base manifest independently.
                    manifest.base = id
                    externalBase = true
                } else {
                    // Bare C4 ID after entries = checkpoint: it names the
                    // accumulated manifest state (all preceding entries and
                    // applied patches). Flush the pending section, then verify.
                    // Consecutive checkpoints verify the same accumulated state;
                    // a checkpoint at EOF is the chain's closing validator
                    // (grammar erratum 2026-07-13).
                    if !patchMode {
                        manifest.entries.append(contentsOf: section)
                    } else if !section.isEmpty {
                        var patch = Manifest()
                        patch.entries = section
                        let base = manifest.base
                        manifest = applyPatch(base: manifest, patch: patch)
                        manifest.base = base // applyPatch builds a fresh manifest; the reference survives
                    }
                    section = []
                    patchMode = true

                    // A resolving decoder MUST verify checkpoints — except
                    // after an unresolved external base reference, where the
                    // accumulated state is unknowable here and verification
                    // defers to the resolver that fetches the base. The
                    // deferral covers EVERY checkpoint of such a stream, not
                    // just the first (found by the libc4 conformance port).
                    if !externalBase && manifest.computeC4ID() != id {
                        throw C4MError.patchIDMismatch
                    }
                }
                firstLine = false
                continue
            }

            // Reject directive lines
            if trimmed.hasPrefix("@") {
                throw C4MError.invalidEntry(lineIndex, "directives not supported: \(trimmed)")
            }

            // Parse as a normal entry
            let entry = try parseEntryLine(line)
            section.append(entry)
            firstLine = false
        }

        // Flush remaining section. A stream may end without a closing
        // validator (the final patch applies unverified — C4M-STANDARD
        // §10.7); a stream whose last line was a bare C4 ID ended with its
        // closing validator, already verified above.
        if !patchMode {
            manifest.entries.append(contentsOf: section)
        } else if !section.isEmpty {
            var patch = Manifest()
            patch.entries = section
            let base = manifest.base
            manifest = applyPatch(base: manifest, patch: patch)
            manifest.base = base
        }

        return manifest
    }

    // MARK: - Bare C4 ID Detection

    /// True if string is exactly a C4 ID (90 chars, starts with "c4").
    static func isBareC4ID(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        return bytes.count == 90 && bytes[0] == UInt8(ascii: "c") && bytes[1] == UInt8(ascii: "4")
    }

    /// True if string is an inline ID list: >90, multiple of 90, all valid C4 IDs.
    static func isInlineIDList(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        let n = bytes.count
        if n <= 90 || n % 90 != 0 { return false }
        if bytes[0] != UInt8(ascii: "c") || bytes[1] != UInt8(ascii: "4") { return false }
        // Validate each 90-char chunk
        for i in stride(from: 0, to: n, by: 90) {
            let chunk = String(bytes: Array(bytes[i ..< i + 90]), encoding: .ascii) ?? ""
            if C4ID(chunk) == nil { return false }
        }
        return true
    }

    // MARK: - Entry Parsing

    private mutating func parseEntryLine(_ line: String) throws -> Entry {
        let lineNum = lineIndex

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

        // "-" (and, on this line, ten dashes) is null. A mode that does not
        // parse is an error naming the line, never a null: a damaged mode
        // used to read as unknown (damaged-line vector).
        guard let mode = FileMode(string: modeStr) else {
            throw C4MError.invalidEntry(lineNum, "invalid mode '\(modeStr)'")
        }

        // Parse timestamp
        var timestamp: Date
        if rest.hasPrefix("- ") || rest.hasPrefix("0 ") {
            timestamp = Date(timeIntervalSince1970: 0)
            rest = String(rest.dropFirst(2))
        } else if rest.count >= 20 && rest[rest.index(rest.startIndex, offsetBy: 4)] == "-" &&
                    rest[rest.index(rest.startIndex, offsetBy: 10)] == "T" {
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
            // Try pretty format
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

        // Parse remaining: size name [link-operator target] [c4id]
        let parsed = try parseEntryFields(rest, lineNum: lineNum, mode: mode)

        var entry = Entry(
            mode: mode,
            timestamp: timestamp,
            size: parsed.size,
            name: parsed.name,
            target: parsed.target,
            c4id: parsed.c4id,
            depth: depth,
            hardLink: parsed.hardLink,
            flowDirection: parsed.flowDirection,
            flowTarget: parsed.flowTarget
        )

        // Detect sequence notation in raw name
        if hasUnescapedSequenceNotation(parsed.rawName) {
            entry.isSequence = true
            entry.pattern = entry.name
        }

        return entry
    }

    /// Result of parsing fields after timestamp.
    private struct ParsedFields {
        var size: Int64
        var name: String
        var rawName: String
        var target: String
        var c4id: C4ID?
        var hardLink: Int
        var flowDirection: FlowDirection
        var flowTarget: String
    }

    /// Parse "size name [link-op target] [c4id]" using character-level scanning.
    private func parseEntryFields(_ line: String, lineNum: Int, mode: FileMode) throws -> ParsedFields {
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
            let sizeStr = Decoder.utf8Slice(chars, sizeStart, pos)
                .replacingOccurrences(of: ",", with: "")
            guard let s = Int64(sizeStr) else {
                throw C4MError.invalidEntry(lineNum, "invalid size '\(sizeStr)'")
            }
            size = s
        }
        // The size token ends at a space: "6x a.txt" read as size 6 and the
        // name "x a.txt", a different entry with no error (damaged-line
        // vector).
        if pos < n && chars[pos] != 0x20 {
            throw C4MError.invalidEntry(lineNum, "invalid size")
        }

        // Skip whitespace
        while pos < n && chars[pos] == 0x20 { pos += 1 }
        guard pos < n else { throw C4MError.invalidEntry(lineNum, "missing name after size") }

        // 2. Parse name (backslash-escaped, no quoting)
        let nameStart = pos
        let (rawName, nameEnd) = try parseName(line, from: pos, lineNum: lineNum)
        let name = rawName
        pos = nameEnd
        let rawNameText = Decoder.utf8Slice(chars, nameStart, pos)

        // Skip whitespace
        while pos < n && chars[pos] == 0x20 { pos += 1 }

        // 3. Check for link operators: ->, <-, <>
        var target = ""
        var hardLink = 0
        var flowDirection = FlowDirection.none
        var flowTarget = ""

        let isSymlink = mode.isSymlink

        if pos + 1 < n && chars[pos] == 0x2D && chars[pos + 1] == 0x3E { // '->'
            pos += 2

            if isSymlink {
                // Symlink mode: -> is always symlink target
                while pos < n && chars[pos] == 0x20 { pos += 1 }
                if pos < n {
                    let (t, tEnd) = parseTarget(line, from: pos)
                    target = t
                    pos = tEnd
                    while pos < n && chars[pos] == 0x20 { pos += 1 }
                }
            } else if pos < n && chars[pos] >= 0x31 && chars[pos] <= 0x39 { // digit 1-9
                // Hard link group number: ->N
                let groupStart = pos
                while pos < n && chars[pos] >= 0x30 && chars[pos] <= 0x39 {
                    pos += 1
                }
                let groupStr = Decoder.utf8Slice(chars, groupStart, pos)
                hardLink = Int(groupStr) ?? 0
                while pos < n && chars[pos] == 0x20 { pos += 1 }
            } else {
                // Skip whitespace after ->
                while pos < n && chars[pos] == 0x20 { pos += 1 }

                // Check what follows
                if pos < n && Decoder.isFlowTargetAt(line, pos: pos) {
                    // Flow target (location:path pattern)
                    flowDirection = .outbound
                    let (ft, ftEnd) = parseFlowTarget(line, from: pos)
                    flowTarget = ft
                    pos = ftEnd
                    while pos < n && chars[pos] == 0x20 { pos += 1 }
                } else {
                    // Ungrouped hard link: the C4 ID field (or its null) is the
                    // only field after the operator. The C4 ID is always the
                    // last field and a target never holds an unescaped space,
                    // so a second field means the first is a target, even when
                    // it starts with "c4" (a null mode, as views carry links,
                    // is not a symlink mode). Taking any "c4" token here read a
                    // link to a C4 ID's text as a hard link and dropped its
                    // target (shared link-target vector, 2026-11-10).
                    let remaining = Decoder.utf8Slice(chars, pos, chars.count).trimmingCharacters(in: .whitespaces)
                    if Decoder.isLoneIDField(remaining) {
                        hardLink = -1
                    } else if pos < n {
                        // Fallback: treat as symlink target
                        let (t, tEnd) = parseTarget(line, from: pos)
                        target = t
                        pos = tEnd
                        while pos < n && chars[pos] == 0x20 { pos += 1 }
                    }
                }
            }
        } else if pos + 1 < n && chars[pos] == 0x3C && chars[pos + 1] == 0x2D { // '<-'
            pos += 2
            while pos < n && chars[pos] == 0x20 { pos += 1 }
            flowDirection = .inbound
            let (ft, ftEnd) = parseFlowTarget(line, from: pos)
            flowTarget = ft
            pos = ftEnd
            while pos < n && chars[pos] == 0x20 { pos += 1 }
        } else if pos + 1 < n && chars[pos] == 0x3C && chars[pos + 1] == 0x3E { // '<>'
            pos += 2
            while pos < n && chars[pos] == 0x20 { pos += 1 }
            flowDirection = .bidirectional
            let (ft, ftEnd) = parseFlowTarget(line, from: pos)
            flowTarget = ft
            pos = ftEnd
            while pos < n && chars[pos] == 0x20 { pos += 1 }
        }

        // 4. Parse C4 ID or null. The field is "-", a C4 ID, or omitted;
        // anything else is an error naming the line. A field that failed to
        // parse used to be dropped and the entry read as having a null ID,
        // which turned a truncated or malformed file into "unknown" with no
        // error: a read error must never become a value, null included.
        var c4id: C4ID? = nil
        if pos < n {
            let remaining = Decoder.utf8Slice(chars, pos, chars.count).trimmingCharacters(in: .whitespaces)
            if remaining.isEmpty || remaining == "-" {
                c4id = nil
            } else if let parsed = C4ID(remaining) {
                c4id = parsed
            } else {
                throw C4MError.invalidEntry(lineNum, "invalid C4 ID '\(remaining)'")
            }
        }

        // Unescape SafeName from the parsed name
        let unescapedName = unsafeName(name)
        // A name is a bare entry name, checked once decoded, so an escaped
        // "/" is refused as surely as a raw one (name-rule vector).
        if isPathName(unescapedName) {
            throw C4MError.invalidEntry(lineNum, "name '\(unescapedName)' is a path, not an entry name (only a directory's trailing / is allowed)")
        }

        return ParsedFields(
            size: size,
            name: unescapedName,
            rawName: rawNameText,
            target: unsafeName(target),
            c4id: c4id,
            hardLink: hardLink,
            flowDirection: flowDirection,
            flowTarget: flowTarget
        )
    }

    /// Parse a backslash-escaped name starting at `from`.
    /// c4m field-boundary escapes: \<space>->space, \"->", \[->[, \]->]
    /// All other backslash sequences pass through for UnsafeName.
    /// Directory names end at / (inclusive).
    /// File names end at space followed by ->, <-, <>, c4 prefix, or -
    private func parseName(_ line: String, from: Int, lineNum: Int) throws -> (String, Int) {
        let chars = Array(line.utf8)
        let n = chars.count
        var pos = from
        var buf: [UInt8] = []

        while pos < n {
            let ch = chars[pos]

            // A backslash always starts a two-byte escape: a c4m field-
            // boundary escape (space, quote, [, ]) becomes its literal, and
            // any other (a SafeName escape such as \\) passes through whole
            // for UnsafeName, so its second byte never starts an escape of
            // its own. A name ending in a backslash read back with its C4 ID
            // swallowed before this (backslash-name vector).
            if ch == 0x5C && pos + 1 < n {
                let next = chars[pos + 1]
                if next == 0x20 || next == 0x22 || next == 0x5B || next == 0x5D {
                    buf.append(next)
                } else {
                    buf.append(ch)
                    buf.append(next)
                }
                pos += 2
                continue
            }

            // A double quote is written \" in a name, and a control byte is
            // encoded by SafeName, so a raw one never comes from a conforming
            // writer: it is damage, refused rather than read into the name
            // (name-escape vector).
            if ch == 0x22 {
                throw C4MError.invalidEntry(lineNum, "name holds a raw '\"' (written \\\" in a name)")
            }
            if ch < 0x20 {
                throw C4MError.invalidEntry(lineNum, "name holds a raw control byte 0x\(String(format: "%02X", ch)) (SafeName encodes it)")
            }

            // A "/" ends a directory's name, and only where the field ends
            // with it. Anything after it but a space is part of the name,
            // which then holds a "/" and is refused with its line once
            // decoded. Before, the name was cut at its first "/" and the
            // rest of the line failed as a C4 ID field, an accident rather
            // than the rule (name-rule vector).
            if ch == 0x2F && (pos + 1 >= n || chars[pos + 1] == 0x20) { // '/'
                buf.append(0x2F)
                pos += 1
                return (String(decoding: buf, as: UTF8.self), pos)
            }

            // Boundary: space(s) followed by a link operator, the c4
            // prefix, or a null "-". Aligned (pretty) forms pad fields with
            // runs of spaces, so the lookahead skips the whole run first.
            if ch == 0x20 && Decoder.isFieldBoundary(chars, at: pos, allowLinkOperators: true) {
                return (String(decoding: buf, as: UTF8.self), pos)
            }
            // A space that is not a field boundary would be part of the name,
            // but a name's space is written "\ ": an unescaped one is damage,
            // often a damaged C4 ID field that would otherwise join the name.
            if ch == 0x20 {
                throw C4MError.invalidEntry(lineNum, "name '\(String(decoding: buf, as: UTF8.self)) …' holds an unescaped space (written \"\\ \" in a name), or its C4 ID field is damaged")
            }

            buf.append(ch)
            pos += 1
        }

        return (String(decoding: buf, as: UTF8.self), pos)
    }

    /// True if the run of spaces starting at `pos` ends the current field:
    /// what follows the run is end of line, a link operator (`-> `, `<- `,
    /// `<> `, `->N`; names only), a C4 ID (`c4`), or a lone `-`.
    static func isFieldBoundary(_ chars: [UInt8], at pos: Int, allowLinkOperators: Bool) -> Bool {
        let n = chars.count
        var j = pos
        while j < n && chars[j] == 0x20 { j += 1 }
        let rest = n - j
        // Trailing padding: the field ended at the first space.
        if rest == 0 { return true }
        if allowLinkOperators {
            // "-> ", "<- ", "<> "
            if rest >= 3 && chars[j + 2] == 0x20 {
                if chars[j] == 0x2D && chars[j + 1] == 0x3E { return true }
                if chars[j] == 0x3C && chars[j + 1] == 0x2D { return true }
                if chars[j] == 0x3C && chars[j + 1] == 0x3E { return true }
            }
            // Hard link group marker "->N", N in 1-9
            if rest >= 3 && chars[j] == 0x2D && chars[j + 1] == 0x3E && chars[j + 2] >= 0x31 && chars[j + 2] <= 0x39 {
                return true
            }
        }
        // "c4"
        if rest >= 2 && chars[j] == 0x63 && chars[j + 1] == 0x34 { return true }
        // "-" at end or "- "
        if chars[j] == 0x2D && (rest == 1 || chars[j + 1] == 0x20) { return true }
        return false
    }

    /// Parse a symlink target starting at `from`.
    /// Unlike names, / is not a boundary (targets can be paths).
    /// Only space and quote backslash escapes are consumed.
    private func parseTarget(_ line: String, from: Int) -> (String, Int) {
        let chars = Array(line.utf8)
        let n = chars.count
        var pos = from
        var buf: [UInt8] = []

        while pos < n {
            let ch = chars[pos]

            // A backslash always starts a two-byte escape (as in names):
            // space and quote become literals, any other passes through.
            if ch == 0x5C && pos + 1 < n {
                let next = chars[pos + 1]
                if next == 0x20 || next == 0x22 {
                    buf.append(next)
                } else {
                    buf.append(ch)
                    buf.append(next)
                }
                pos += 2
                continue
            }

            // The pretty form pads before the C4 ID field; testing only the
            // next character let that padding join the target (link-target
            // vector).
            if ch == 0x20 && Decoder.isFieldBoundary(chars, at: pos, allowLinkOperators: false) {
                return (String(decoding: buf, as: UTF8.self), pos)
            }

            buf.append(ch)
            pos += 1
        }

        return (String(decoding: buf, as: UTF8.self), pos)
    }

    /// The text of bytes chars[a..<b], decoded as UTF-8. Every field
    /// parser walks Array(line.utf8), so its positions are byte offsets;
    /// slicing the String by Character offsets instead skipped one
    /// position for each extra byte of a non-ASCII name, so any line whose
    /// name was not ASCII lost the start of its C4 ID and was refused
    /// (unicode-name vector, 2026-11-11).
    static func utf8Slice(_ chars: [UInt8], _ a: Int, _ b: Int) -> String {
        String(decoding: chars[a..<b], as: UTF8.self)
    }

    /// Parse a flow target (location:path) starting at pos.
    private func parseFlowTarget(_ line: String, from: Int) -> (String, Int) {
        let chars = Array(line.utf8)
        let n = chars.count
        var pos = from
        let start = pos

        while pos < n {
            let ch = chars[pos]
            if ch == 0x20 && Decoder.isFieldBoundary(chars, at: pos, allowLinkOperators: false) {
                return (Decoder.utf8Slice(chars, start, pos), pos)
            }
            pos += 1
        }

        return (Decoder.utf8Slice(chars, start, chars.count), pos)
    }

    /// Whether `s`, the rest of a line after a link operator, is exactly one
    /// field that is a C4 ID or the null "-". A field ends at an unescaped space.
    static func isLoneIDField(_ s: String) -> Bool {
        if s == "-" { return true }
        guard s.hasPrefix("c4") else { return false }
        let bytes = Array(s.utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x5C { i += 2; continue } // backslash escape
            if bytes[i] == 0x20 { return false }
            i += 1
        }
        return C4ID(s) != nil
    }

    /// Check if text at position matches flow target pattern: [a-zA-Z][a-zA-Z0-9_-]*:
    static func isFlowTargetAt(_ s: String, pos: Int) -> Bool {
        let chars = Array(s.utf8)
        let n = chars.count
        guard pos < n else { return false }
        let ch = chars[pos]
        if !((ch >= 0x61 && ch <= 0x7A) || (ch >= 0x41 && ch <= 0x5A)) {
            return false
        }
        var i = pos + 1
        while i < n {
            let c = chars[i]
            if c == 0x3A { return true } // ':'
            if c == 0x20 { return false }
            if !((c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) ||
                 (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x2D) {
                return false
            }
            i += 1
        }
        return false
    }

    /// Check if raw text contains unescaped sequence notation [digits].
    private func hasUnescapedSequenceNotation(_ raw: String) -> Bool {
        // Replace all escape sequences with neutral characters
        var buf = ""
        let chars = Array(raw.utf8)
        var i = 0
        while i < chars.count {
            if chars[i] == 0x5C && i + 1 < chars.count {
                buf += "__"
                i += 2
                continue
            }
            buf.append(Character(UnicodeScalar(chars[i])))
            i += 1
        }
        let regex = try! NSRegularExpression(pattern: #"\[([0-9,\-:]+)\]"#)
        let nsRange = NSRange(buf.startIndex ..< buf.endIndex, in: buf)
        return regex.firstMatch(in: buf, range: nsRange) != nil
    }

    // MARK: - Timestamp Parsing

    /// Parse a timestamp string in various accepted formats.
    static func parseTimestamp(_ s: String) -> Date? {
        // Canonical: 2006-01-02T15:04:05Z
        let canonical = ISO8601DateFormatter()
        canonical.formatOptions = [.withInternetDateTime]
        canonical.timeZone = TimeZone(identifier: "UTC")
        if let d = canonical.date(from: s) { return d }

        // RFC3339 with offset
        let rfc3339 = ISO8601DateFormatter()
        rfc3339.formatOptions = [.withInternetDateTime]
        if let d = rfc3339.date(from: s) { return d }

        // Pretty format
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
