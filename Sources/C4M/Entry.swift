import Foundation

/// Direction of a flow link.
public enum FlowDirection: Int, Sendable, Hashable, Codable {
    case none = 0          // No flow link
    case outbound = 1      // -> (content here propagates there)
    case inbound = 2       // <- (content there propagates here)
    case bidirectional = 3 // <> (bidirectional sync)

    /// The string operator for this direction.
    public var operatorString: String {
        switch self {
        case .none: return ""
        case .outbound: return "->"
        case .inbound: return "<-"
        case .bidirectional: return "<>"
        }
    }
}

/// A single entry in a C4M manifest: file, directory, symlink, or sequence.
public struct Entry: Sendable, Hashable, Codable, CustomStringConvertible {

    /// Unix file mode (type + permissions).
    public var mode: FileMode

    /// UTC timestamp.
    public var timestamp: Date

    /// File size in bytes. Negative means null/unknown.
    public var size: Int64

    /// File or directory name. Directories end with "/".
    public var name: String

    /// Symlink target path (empty if not a symlink).
    public var target: String

    /// Content identifier. Nil means uncomputed.
    public var c4id: C4ID?

    /// Nesting depth (0 = top level).
    public var depth: Int

    /// True if this entry uses sequence notation.
    public var isSequence: Bool

    /// Original sequence pattern (e.g. "frame.[0001-0100].exr").
    public var pattern: String

    /// Hard link marker: 0=none, -1=ungrouped hard link (->), >0=group N (->N)
    public var hardLink: Int

    /// Flow link direction.
    public var flowDirection: FlowDirection

    /// Flow link target (e.g. "studio:inbox/").
    public var flowTarget: String

    // MARK: - Initialisers

    public init(
        mode: FileMode = .null,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        size: Int64 = 0,
        name: String,
        target: String = "",
        c4id: C4ID? = nil,
        depth: Int = 0,
        isSequence: Bool = false,
        pattern: String = "",
        hardLink: Int = 0,
        flowDirection: FlowDirection = .none,
        flowTarget: String = ""
    ) {
        self.mode = mode
        self.timestamp = timestamp
        self.size = size
        self.name = name
        self.target = target
        self.c4id = c4id
        self.depth = depth
        self.isSequence = isSequence
        self.pattern = pattern
        self.hardLink = hardLink
        self.flowDirection = flowDirection
        self.flowTarget = flowTarget
    }

    // MARK: - Queries

    /// True if the entry is a directory (by mode or trailing slash).
    public var isDir: Bool { mode.isDir || name.hasSuffix("/") }

    /// True if the entry is a symbolic link.
    public var isSymlink: Bool { mode.isSymlink }

    /// True if this entry has a flow link declaration.
    public var isFlowLinked: Bool { flowDirection != .none }

    /// True if any metadata field holds a null sentinel.
    public var hasNullValues: Bool {
        let nullMode = mode.isNull && !isDir && !isSymlink && !mode.isNamedPipe && !mode.isSocket && !mode.isBlock && !mode.isChar
        let nullTimestamp = timestamp == Entry.nullTimestamp
        let nullSize = size < 0
        return nullMode || nullTimestamp || nullSize
    }

    /// The Unix epoch sentinel used for null/unspecified timestamps.
    public static let nullTimestamp = Date(timeIntervalSince1970: 0)

    // MARK: - Formatting

    /// Canonical form (no indentation, single spaces, no commas in sizes).
    /// Null mode renders as "-" (single dash), C4 ID or "-" always last.
    public var canonical: String {
        // Mode: null renders as single dash
        let modeStr: String
        if mode.isNull && !isDir && !isSymlink {
            modeStr = "-"
        } else {
            modeStr = mode.description
        }

        let timeStr = Entry.canonicalTimestamp(timestamp)
        let sizeStr = size < 0 ? "-" : "\(size)"
        let nameStr = Entry.formatName(name, isSequence: isSequence)

        var parts = [modeStr, timeStr, sizeStr, nameStr]

        // Link operators
        if !target.isEmpty {
            parts.append("->")
            parts.append(Entry.formatTarget(target))
        } else if hardLink != 0 {
            if hardLink < 0 {
                parts.append("->")
            } else {
                parts.append("->\(hardLink)")
            }
        } else if flowDirection != .none {
            parts.append(flowDirection.operatorString)
            parts.append(flowTarget)
        }

        // C4 ID or "-" always last
        if let id = c4id, !id.isNil {
            parts.append(id.string)
        } else {
            parts.append("-")
        }

        return parts.joined(separator: " ")
    }

    /// Human-readable representation with indentation.
    public func format(indentWidth: Int = 0, displayFormat: Bool = false) -> String {
        let indent = String(repeating: " ", count: depth * indentWidth)

        let modeStr: String
        if mode.isNull && !isDir && !isSymlink {
            modeStr = "----------"
        } else {
            modeStr = mode.description
        }

        let timeStr: String
        if timestamp == Entry.nullTimestamp {
            timeStr = "-"
        } else {
            timeStr = Entry.canonicalTimestamp(timestamp)
        }

        let sizeStr: String
        if size < 0 {
            sizeStr = "-"
        } else if displayFormat {
            sizeStr = Entry.formatSizeWithCommas(size)
        } else {
            sizeStr = "\(size)"
        }

        let nameStr = Entry.formatName(name, isSequence: isSequence)

        var parts = [indent + modeStr, timeStr, sizeStr, nameStr]

        // Link operators
        if !target.isEmpty {
            parts.append("->")
            parts.append(Entry.formatTarget(target))
        } else if hardLink != 0 {
            if hardLink < 0 {
                parts.append("->")
            } else {
                parts.append("->\(hardLink)")
            }
        } else if flowDirection != .none {
            parts.append(flowDirection.operatorString)
            parts.append(flowTarget)
        }

        // C4 ID or "-" always last
        if let id = c4id, !id.isNil {
            parts.append(id.string)
        } else {
            parts.append("-")
        }

        return parts.joined(separator: " ")
    }

    public var description: String { format() }

    // MARK: - Internal Formatting Helpers

    /// ISO 8601 UTC timestamp string for canonical form.
    static func canonicalTimestamp(_ date: Date) -> String {
        if date == nullTimestamp { return "-" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// Backslash-escape a name for c4m output.
    /// SafeName encoding first, then c4m field-boundary escaping.
    /// No quoting mechanism — all unsafe chars are backslash-escaped.
    static func formatName(_ name: String, isSequence: Bool = false) -> String {
        if isSequence {
            return formatSequenceName(name)
        }

        let safe = safeName(name)

        // Directories: escape base part, keep trailing /
        if safe.hasSuffix("/") {
            let base = String(safe.dropLast())
            return escapeC4MName(base, isSequence: false) + "/"
        }

        return escapeC4MName(safe, isSequence: false)
    }

    /// Backslash-escape a symlink target for c4m output.
    /// Targets don't get bracket escaping.
    static func formatTarget(_ target: String) -> String {
        let safe = safeName(target)
        if !safe.contains(" ") && !safe.contains("\"") {
            return safe
        }
        var result = ""
        for ch in safe {
            switch ch {
            case " ":  result += "\\ "
            case "\"": result += "\\\""
            default:   result.append(ch)
            }
        }
        return result
    }

    /// Backslash-escape c4m field-boundary characters: space, quote,
    /// and (for non-sequence names) brackets.
    private static func escapeC4MName(_ s: String, isSequence: Bool) -> String {
        var needsEscape = s.contains(" ") || s.contains("\"")
        if !isSequence && (s.contains("[") || s.contains("]")) {
            needsEscape = true
        }
        if !needsEscape { return s }

        var result = ""
        for ch in s {
            switch ch {
            case " ":  result += "\\ "
            case "\"": result += "\\\""
            case "[":
                if !isSequence { result += "\\[" } else { result.append(ch) }
            case "]":
                if !isSequence { result += "\\]" } else { result.append(ch) }
            default:
                result.append(ch)
            }
        }
        return result
    }

    /// Format a sequence name: escape prefix and suffix, leave range notation.
    private static func formatSequenceName(_ name: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"\[([0-9,\-:]+)\]"#)
        let nsRange = NSRange(name.startIndex ..< name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: nsRange) else {
            return name
        }
        let fullRange = Range(match.range, in: name)!
        let prefix = String(name[name.startIndex ..< fullRange.lowerBound])
        let rangePart = String(name[fullRange])
        let suffix = String(name[fullRange.upperBound ..< name.endIndex])
        return escapeSequenceNotation(prefix) + rangePart + escapeSequenceNotation(suffix)
    }

    /// Escape c4m-specific syntax characters in sequence prefix/suffix parts.
    private static func escapeSequenceNotation(_ s: String) -> String {
        let safe = safeName(s)
        var result = ""
        for ch in safe {
            switch ch {
            case " ":  result += "\\ "
            case "\"": result += "\\\""
            case "[":  result += "\\["
            case "]":  result += "\\]"
            default:   result.append(ch)
            }
        }
        return result
    }

    /// Format a size with thousands separators.
    static func formatSizeWithCommas(_ size: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: size)) ?? "\(size)"
    }
}
