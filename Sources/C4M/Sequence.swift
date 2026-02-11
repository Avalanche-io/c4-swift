import Foundation

/// A numeric range within a sequence pattern.
public struct SequenceRange: Sendable, Hashable, Codable {
    public var start: Int
    public var end: Int
    public var step: Int

    public init(start: Int, end: Int, step: Int = 1) {
        self.start = start
        self.end = end
        self.step = step
    }
}

/// A file sequence pattern like "frame.[0001-0100].exr".
public struct Sequence: Sendable, Hashable, Codable {

    /// Text before the bracket range.
    public var prefix: String

    /// Text after the bracket range.
    public var suffix: String

    /// The numeric ranges.
    public var ranges: [SequenceRange]

    /// Number of digits for zero-padding.
    public var padding: Int

    public init(prefix: String, suffix: String, ranges: [SequenceRange], padding: Int) {
        self.prefix = prefix
        self.suffix = suffix
        self.ranges = ranges
        self.padding = padding
    }

    // MARK: - Expansion

    /// Return all filenames in the sequence.
    public func expand() -> [String] {
        var files: [String] = []
        for r in ranges {
            var i = r.start
            while i <= r.end {
                let numStr = String(format: "%0\(padding)d", i)
                files.append(prefix + numStr + suffix)
                i += r.step
            }
        }
        return files
    }

    /// Total number of files in the sequence.
    public var count: Int {
        ranges.reduce(0) { $0 + ($1.end - $1.start) / $1.step + 1 }
    }

    /// Check whether a frame number is contained in the sequence.
    public func contains(frame: Int) -> Bool {
        for r in ranges {
            if frame >= r.start && frame <= r.end && (frame - r.start) % r.step == 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Parsing

    /// Regex matching sequence bracket notation.
    private static let sequencePattern = try! NSRegularExpression(pattern: #"\[([0-9,\-:]+)\]"#)

    /// Parse a pattern like "frame.[0001-0100].exr".
    public static func parse(_ pattern: String) throws -> Sequence {
        let nsRange = NSRange(pattern.startIndex ..< pattern.endIndex, in: pattern)
        guard let match = sequencePattern.firstMatch(in: pattern, range: nsRange) else {
            throw C4MError.invalidEntry(0, "no sequence pattern found in '\(pattern)'")
        }

        let fullRange = Range(match.range, in: pattern)!
        let specRange = Range(match.range(at: 1), in: pattern)!

        var prefix = String(pattern[pattern.startIndex ..< fullRange.lowerBound])
        let suffix = String(pattern[fullRange.upperBound ..< pattern.endIndex])

        // Handle backslash-space in prefix
        prefix = prefix.replacingOccurrences(of: "\\ ", with: " ")

        let spec = String(pattern[specRange])
        let parts = spec.split(separator: ",")

        var ranges: [SequenceRange] = []
        var pad = 0

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)

            // Check for step notation
            var mainPart = trimmed
            var step = 1
            if let colonIdx = trimmed.firstIndex(of: ":") {
                let stepStr = trimmed[trimmed.index(after: colonIdx)...]
                guard let s = Int(stepStr) else {
                    throw C4MError.invalidEntry(0, "invalid step value: \(stepStr)")
                }
                step = s
                mainPart = String(trimmed[trimmed.startIndex ..< colonIdx])
            }

            // Check for range
            if let dashIdx = mainPart.firstIndex(of: "-"), dashIdx != mainPart.startIndex {
                let startStr = String(mainPart[mainPart.startIndex ..< dashIdx])
                let endStr = String(mainPart[mainPart.index(after: dashIdx)...])

                if pad == 0 { pad = startStr.count }

                guard let start = Int(startStr), let end = Int(endStr) else {
                    throw C4MError.invalidEntry(0, "invalid range: \(mainPart)")
                }
                guard start <= end else {
                    throw C4MError.invalidEntry(0, "start \(start) > end \(end)")
                }
                ranges.append(SequenceRange(start: start, end: end, step: step))
            } else {
                // Single frame
                if pad == 0 { pad = mainPart.count }
                guard let frame = Int(mainPart) else {
                    throw C4MError.invalidEntry(0, "invalid frame number: \(mainPart)")
                }
                ranges.append(SequenceRange(start: frame, end: frame, step: 1))
            }
        }

        return Sequence(prefix: prefix, suffix: suffix, ranges: ranges, padding: pad)
    }
}

// MARK: - Detection

/// Check if a filename contains sequence bracket notation.
public func isSequencePattern(_ pattern: String) -> Bool {
    (try? Sequence.parse(pattern)) != nil
}

/// Convenience: expand a pattern to individual filenames.
public func expandSequencePattern(_ pattern: String) throws -> [String] {
    try Sequence.parse(pattern).expand()
}

/// Detect and collapse numbered file runs into sequence entries.
public func detectSequences(in manifest: Manifest, minLength: Int = 3) -> Manifest {
    let effectiveMin = max(2, minLength)
    let framePattern = try! NSRegularExpression(pattern: #"^(.*?)(\d+)(.*)$"#)

    struct FileGroup {
        var prefix: String
        var suffix: String
        var entries: [Int: (Entry, Int)] // frameNum -> (entry, original index)
        var padding: Int
    }

    var groups: [String: FileGroup] = [:]
    var result = Manifest(version: manifest.version)

    for (idx, entry) in manifest.entries.enumerated() {
        if entry.isDir { continue }

        // Extract basename and directory using simple string ops
        let dir: String
        let basename: String
        if let slashIdx = entry.name.lastIndex(of: "/") {
            dir = String(entry.name[...slashIdx])
            basename = String(entry.name[entry.name.index(after: slashIdx)...])
        } else {
            dir = ""
            basename = entry.name
        }

        let nsRange = NSRange(basename.startIndex ..< basename.endIndex, in: basename)
        guard let match = framePattern.firstMatch(in: basename, range: nsRange) else {
            result.addEntry(entry)
            continue
        }

        let prefixRange = Range(match.range(at: 1), in: basename)!
        let numRange = Range(match.range(at: 2), in: basename)!
        let suffixRange = Range(match.range(at: 3), in: basename)!

        let prefix = String(basename[prefixRange])
        let numStr = String(basename[numRange])
        let suffix = String(basename[suffixRange])

        guard let frameNum = Int(numStr) else {
            result.addEntry(entry)
            continue
        }

        let key = "\(dir)|\(prefix)|\(suffix)|\(numStr.count)"

        if groups[key] == nil {
            groups[key] = FileGroup(prefix: dir + prefix, suffix: suffix, entries: [:], padding: numStr.count)
        }
        groups[key]!.entries[frameNum] = (entry, idx)
    }

    for (_, group) in groups {
        if group.entries.count < effectiveMin {
            for (_, pair) in group.entries { result.addEntry(pair.0) }
            continue
        }

        let frames = group.entries.keys.sorted()
        let ranges = findRanges(frames)

        for r in ranges {
            if r.count >= effectiveMin {
                let pattern = "\(group.prefix)[\(String(format: "%0\(group.padding)d", r.start))-\(String(format: "%0\(group.padding)d", r.end))]\(group.suffix)"

                var totalSize: Int64 = 0
                var latestTime = Date.distantPast

                for i in r.start ... r.end {
                    guard let (entry, _) = group.entries[i] else { continue }
                    totalSize += entry.size
                    if entry.timestamp > latestTime { latestTime = entry.timestamp }
                }

                let firstEntry = group.entries[r.start]!.0
                let seqEntry = Entry(
                    mode: firstEntry.mode,
                    timestamp: latestTime,
                    size: totalSize,
                    name: pattern,
                    depth: firstEntry.depth,
                    isSequence: true,
                    pattern: pattern
                )
                result.addEntry(seqEntry)
            } else {
                for i in r.start ... r.end {
                    if let (entry, _) = group.entries[i] { result.addEntry(entry) }
                }
            }
        }
    }

    // Add directory entries
    for entry in manifest.entries where entry.isDir {
        result.addEntry(entry)
    }

    return result
}

// MARK: - Range Finding

private struct FrameRange {
    var start: Int
    var end: Int
    var count: Int
}

private func findRanges(_ frames: [Int]) -> [FrameRange] {
    guard !frames.isEmpty else { return [] }

    var ranges: [FrameRange] = []
    var start = frames[0]
    var end = frames[0]
    var count = 1

    for i in 1 ..< frames.count {
        if frames[i] == end + 1 {
            end = frames[i]
            count += 1
        } else {
            ranges.append(FrameRange(start: start, end: end, count: count))
            start = frames[i]
            end = frames[i]
            count = 1
        }
    }

    ranges.append(FrameRange(start: start, end: end, count: count))
    return ranges
}
