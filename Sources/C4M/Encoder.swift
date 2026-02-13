import Foundation

/// Writes manifests to the C4M text format.
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
    public func encode(_ manifest: Manifest) -> String {
        var m = manifest
        m.sortEntries()

        var buf = "@c4m \(m.version)\n"

        // Write metadata
        if !m.data.isNil {
            buf += "@data \(m.data.string)\n"
        }

        // Write base
        if !m.base.isNil {
            buf += "@base \(m.base.string)\n"
        }

        // Compute formatting parameters for pretty mode
        var maxSize: Int64 = 0
        var c4IDColumn = 80
        if pretty {
            for e in m.entries {
                if e.size > maxSize { maxSize = e.size }
            }
            c4IDColumn = calculateC4IDColumn(m, maxSize: maxSize)
        }

        // Separate regular entries from remove-layer entries
        let regularEntries = m.entries.filter { !$0.inRemoveLayer }
        let removeEntries = m.entries.filter { $0.inRemoveLayer }

        // Write regular entries
        for entry in regularEntries {
            if pretty {
                buf += formatEntryPretty(entry, maxSize: maxSize, c4IDColumn: c4IDColumn)
            } else {
                buf += entry.format(indentWidth: indentWidth)
            }
            buf += "\n"
        }

        // Write layers (non-remove layers first)
        for layer in m.layers where layer.type != .remove {
            buf += writeLayer(layer)
        }

        // Write remove layer with its entries
        if !removeEntries.isEmpty {
            for layer in m.layers where layer.type == .remove {
                buf += writeLayer(layer)
            }
            if m.layers.first(where: { $0.type == .remove }) == nil {
                buf += "@remove\n"
            }
            for entry in removeEntries {
                if pretty {
                    buf += formatEntryPretty(entry, maxSize: maxSize, c4IDColumn: c4IDColumn)
                } else {
                    buf += entry.format(indentWidth: indentWidth)
                }
                buf += "\n"
            }
        } else {
            // Write any remove layers even if no entries
            for layer in m.layers where layer.type == .remove {
                buf += writeLayer(layer)
            }
        }

        return buf
    }

    // MARK: - Layer Output

    private func writeLayer(_ layer: Layer) -> String {
        var buf = ""
        switch layer.type {
        case .add:    buf += "@layer\n"
        case .remove: buf += "@remove\n"
        }

        if !layer.by.isEmpty {
            buf += "@by \(layer.by)\n"
        }
        if let t = layer.time {
            buf += "@time \(Entry.canonicalTimestamp(t))\n"
        }
        if !layer.note.isEmpty {
            buf += "@note \(layer.note)\n"
        }
        if !layer.data.isNil {
            buf += "@data \(layer.data.string)\n"
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
            let timeLen = 24 // approximate pretty timestamp width
            let nameLen = Entry.formatName(entry.name).count
            var lineLen = indent + modeLen + 1 + timeLen + 1 + maxSizeWidth + 1 + nameLen
            if !entry.target.isEmpty {
                lineLen += 4 + entry.target.count
            }
            if lineLen > maxLen { maxLen = lineLen }
        }

        var column = 80
        while maxLen + 10 > column { column += 10 }
        return column
    }

    private func formatEntryPretty(_ entry: Entry, maxSize: Int64, c4IDColumn: Int) -> String {
        let indent = String(repeating: " ", count: entry.depth * indentWidth)

        let modeStr: String
        if entry.mode.isNull && !entry.isDir && !entry.isSymlink {
            modeStr = "----------"
        } else {
            modeStr = entry.mode.description
        }

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

        let nameStr = Entry.formatName(entry.name)

        var parts = [indent + modeStr, timeStr, sizeStr, nameStr]
        if !entry.target.isEmpty {
            parts.append("->")
            parts.append(Entry.formatTarget(entry.target))
        }

        let baseLine = parts.joined(separator: " ")

        if !entry.c4id.isNil {
            let padding = max(10, c4IDColumn - baseLine.count)
            return baseLine + String(repeating: " ", count: padding) + entry.c4id.string
        }

        return baseLine
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
    /// Encode to canonical C4M string.
    public func marshal() -> String {
        Encoder().encode(self)
    }

    /// Encode to pretty-printed C4M string.
    public func marshalPretty() -> String {
        Encoder(pretty: true).encode(self)
    }
}
