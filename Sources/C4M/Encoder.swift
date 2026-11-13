import Foundation

/// Writes manifests to the C4M text format.
/// Output is entry-only: no header, no directives.
public struct Encoder: Sendable {

    /// Enable pretty-printing (aligned columns, comma sizes, local timestamps).
    public var pretty: Bool

    /// Indentation width per nesting level (default 2).
    public var indentWidth: Int

    public init(pretty: Bool = false, indentWidth: Int = 2) {
        self.pretty = pretty
        self.indentWidth = indentWidth
    }

    /// Encode a manifest to its C4M text representation.
    /// Entry-only: no header, no directives. A set `base` is written first,
    /// as a bare C4 ID line; a manifest with no base has no bare line.
    ///
    /// Throws `C4MError.pathTraversal` for a name the format forbids at any
    /// depth (a name holding `/` other than a directory's trailing one, or
    /// `.`, `..`): no conforming c4m spells it, so the encoder writes no
    /// text a reader would refuse, as Go's encoder does. Through 1.0.x encode
    /// could not refuse and wrote such names out (decided 2026-11-13 by the
    /// release lead; reversible; a 1.1 API change).
    public func encode(_ manifest: Manifest) throws -> String {
        if let bad = manifest.entries.first(where: { isPathName($0.name) }) {
            throw C4MError.pathTraversal(bad.name)
        }
        var m = manifest
        m.sortEntries()

        // Compute formatting parameters for pretty mode
        var maxSize: Int64 = 0
        var c4IDColumn = 80
        if pretty {
            for e in m.entries {
                if e.size > maxSize { maxSize = e.size }
            }
            c4IDColumn = calculateC4IDColumn(m, maxSize: maxSize)
        }

        var buf = ""

        // A first-line bare ID is the external base this description refines
        // (SPECIFICATION.md, external base reference). The decoder keeps it
        // in `base`; writing it back keeps the round trip honest. Through
        // 2026-11-13 it was dropped, so encoding a decoded block turned it
        // into a standalone description of its own entries (c4 #145).
        if let base = m.base, !base.isNil {
            buf += base.string
            buf += "\n"
        }

        // Write entries
        for entry in m.entries {
            if pretty {
                buf += formatEntryPretty(entry, maxSize: maxSize, c4IDColumn: c4IDColumn)
            } else {
                let indent = String(repeating: " ", count: entry.depth * indentWidth)
                buf += indent + entry.canonical
            }
            buf += "\n"
        }

        // Write inline range data lines (bare-concatenated ID lists).
        if !m.rangeData.isEmpty {
            let sortedKeys = m.rangeData.keys.sorted { $0.string < $1.string }
            for key in sortedKeys {
                if let line = m.rangeData[key] {
                    buf += line
                    buf += "\n"
                }
            }
        }

        return buf
    }

    // MARK: - Pretty Printing

    private func calculateC4IDColumn(_ m: Manifest, maxSize: Int64) -> Int {
        let maxSizeWidth = Entry.formatSizeWithCommas(maxSize).count

        var maxLen = 0
        for entry in m.entries {
            let indent = entry.depth * indentWidth
            let modeLen = 10
            let timeLen = 24
            let nameLen = Entry.formatName(entry.name, isSequence: entry.isSequence).count
            var lineLen = indent + modeLen + 1 + timeLen + 1 + maxSizeWidth + 1 + nameLen

            if !entry.target.isEmpty {
                lineLen += 4 + entry.target.count
            } else if entry.hardLink != 0 {
                lineLen += entry.hardLink < 0 ? 3 : 4
            } else if entry.flowDirection != .none {
                lineLen += 1 + entry.flowDirection.operatorString.count + 1 + entry.flowTarget.count
            }

            if lineLen > maxLen { maxLen = lineLen }
        }

        var column = 80
        while maxLen + 10 > column { column += 10 }
        return column
    }

    private func formatEntryPretty(_ entry: Entry, maxSize: Int64, c4IDColumn: Int) -> String {
        let indent = String(repeating: " ", count: entry.depth * indentWidth)

        // Null is "-" in every form; "----------" is the known zero mode
        // and must survive a round trip.
        let modeStr = entry.mode.description

        let timeStr: String
        if entry.timestamp == Entry.nullTimestamp {
            timeStr = "-                       "
        } else {
            timeStr = formatTimestampPretty(entry.timestamp)
        }

        let sizeStr: String
        if entry.sizeIsNull {
            let maxWidth = Entry.formatSizeWithCommas(maxSize).count
            sizeStr = String(repeating: " ", count: maxWidth - 1) + "-"
        } else {
            sizeStr = formatSizePretty(entry.size, maxSize: maxSize)
        }

        let nameStr = Entry.formatName(entry.name, isSequence: entry.isSequence)

        var parts = [indent + modeStr, timeStr, sizeStr, nameStr]

        // Link operators
        if !entry.target.isEmpty {
            parts.append("->")
            parts.append(Entry.formatTarget(entry.target))
        } else if entry.hardLink != 0 {
            if entry.hardLink < 0 {
                parts.append("->")
            } else {
                parts.append("->\(entry.hardLink)")
            }
        } else if entry.flowDirection != .none {
            parts.append(entry.flowDirection.operatorString)
            parts.append(entry.flowTarget)
        }

        let baseLine = parts.joined(separator: " ")

        // C4 ID or "-" always last, with column alignment
        let padding = max(10, c4IDColumn - baseLine.count)
        if let id = entry.c4id, !id.isNil {
            return baseLine + String(repeating: " ", count: padding) + id.string
        }
        return baseLine + String(repeating: " ", count: padding) + "-"
    }

    private func formatTimestampPretty(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM dd HH:mm:ss yyyy zzz"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func formatSizePretty(_ size: Int64, maxSize: Int64) -> String {
        let sizeStr = Entry.formatSizeWithCommas(size)
        let maxStr = Entry.formatSizeWithCommas(maxSize)
        let padding = maxStr.count - sizeStr.count
        return String(repeating: " ", count: padding) + sizeStr
    }
}

// MARK: - Convenience

extension Manifest {
    /// Encode to C4M string.
    public func marshal() throws -> String {
        try Encoder().encode(self)
    }

    /// Encode to pretty-printed C4M string.
    public func marshalPretty() throws -> String {
        try Encoder(pretty: true).encode(self)
    }
}
