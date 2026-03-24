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
    /// Entry-only: no header, no directives.
    public func encode(_ manifest: Manifest) -> String {
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

        let modeStr = entry.mode.description

        let timeStr: String
        if entry.timestamp == Entry.nullTimestamp {
            timeStr = "-                       "
        } else {
            timeStr = formatTimestampPretty(entry.timestamp)
        }

        let sizeStr: String
        if entry.size < 0 {
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
    public func marshal() -> String {
        Encoder().encode(self)
    }

    /// Encode to pretty-printed C4M string.
    public func marshalPretty() -> String {
        Encoder(pretty: true).encode(self)
    }
}
