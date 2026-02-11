import Foundation

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

    /// Content identifier.
    public var c4id: C4ID

    /// Nesting depth (0 = top level).
    public var depth: Int

    /// True if this entry uses sequence notation.
    public var isSequence: Bool

    /// Original sequence pattern (e.g. "frame.[0001-0100].exr").
    public var pattern: String

    /// True if this entry belongs to a @remove layer.
    public var inRemoveLayer: Bool

    // MARK: - Initialisers

    public init(
        mode: FileMode = .null,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        size: Int64 = 0,
        name: String,
        target: String = "",
        c4id: C4ID = .void,
        depth: Int = 0,
        isSequence: Bool = false,
        pattern: String = "",
        inRemoveLayer: Bool = false
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
        self.inRemoveLayer = inRemoveLayer
    }

    // MARK: - Queries

    /// True if the entry is a directory (by mode or trailing slash).
    public var isDir: Bool { mode.isDir || name.hasSuffix("/") }

    /// True if the entry is a symbolic link.
    public var isSymlink: Bool { mode.isSymlink }

    /// True if any metadata field holds a null sentinel.
    public var hasNullValues: Bool {
        let nullMode = mode.isNull && !isDir && !isSymlink
        let nullTimestamp = timestamp == Entry.nullTimestamp
        let nullSize = size < 0
        return nullMode || nullTimestamp || nullSize
    }

    /// The Unix epoch sentinel used for null/unspecified timestamps.
    public static let nullTimestamp = Date(timeIntervalSince1970: 0)

    // MARK: - Formatting

    /// Canonical form (no indentation, single spaces, no commas in sizes).
    public var canonical: String {
        var parts: [String] = []
        parts.append(mode.description)
        parts.append(Entry.canonicalTimestamp(timestamp))
        parts.append(size < 0 ? "-" : "\(size)")
        parts.append(Entry.formatName(name))
        if !target.isEmpty {
            parts.append("->")
            parts.append(Entry.formatTarget(target))
        }
        if !c4id.isNil {
            parts.append(c4id.string)
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

        let nameStr = Entry.formatName(name)

        var parts = [indent + modeStr, timeStr, sizeStr, nameStr]

        if !target.isEmpty {
            parts.append("->")
            parts.append(Entry.formatTarget(target))
        }

        if !c4id.isNil {
            parts.append(c4id.string)
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

    /// Quote a name if it contains special characters.
    static func formatName(_ name: String) -> String {
        // Directories (trailing /) are never quoted
        if name.hasSuffix("/") {
            var escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
            return escaped
        }

        let needsQuotes = name.contains(" ") || name.contains("\"") ||
                          name.contains("\\") || name.contains("\n") ||
                          name != name.trimmingCharacters(in: .whitespaces)

        if !needsQuotes { return name }

        var escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// Quote a symlink target if it contains special characters.
    static func formatTarget(_ target: String) -> String {
        let needsQuotes = target.contains(" ") || target.contains("\"") ||
                          target.contains("\\") || target.contains("\n") ||
                          target != target.trimmingCharacters(in: .whitespaces)

        if !needsQuotes { return target }

        var escaped = target.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// Format a size with thousands separators.
    static func formatSizeWithCommas(_ size: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: size)) ?? "\(size)"
    }
}
