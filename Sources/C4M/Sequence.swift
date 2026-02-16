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
/// Maintains the original entry order so depth-based hierarchy is preserved.
public func detectSequences(in manifest: Manifest, minLength: Int = 3) -> Manifest {
    let effectiveMin = max(2, minLength)
    let framePattern = try! NSRegularExpression(pattern: #"^(.*?)(\d+)(.*)$"#)

    struct FrameInfo {
        var key: String
        var frameNum: Int
    }

    struct GroupInfo {
        var prefix: String
        var suffix: String
        var padding: Int
        var depth: Int
        var frames: [(frameNum: Int, index: Int)]
    }

    // First pass: identify groups by scanning entries in order.
    // Use depth in the key so files at different depths aren't merged.
    var groups: [String: GroupInfo] = [:]
    var entryFrame: [Int: FrameInfo] = [:]  // entry index -> frame info

    for (idx, entry) in manifest.entries.enumerated() {
        if entry.isDir || entry.isSequence { continue }

        let nsRange = NSRange(entry.name.startIndex ..< entry.name.endIndex, in: entry.name)
        guard let match = framePattern.firstMatch(in: entry.name, range: nsRange) else { continue }

        let prefixRange = Range(match.range(at: 1), in: entry.name)!
        let numRange = Range(match.range(at: 2), in: entry.name)!
        let suffixRange = Range(match.range(at: 3), in: entry.name)!

        let prefix = String(entry.name[prefixRange])
        let numStr = String(entry.name[numRange])
        let suffix = String(entry.name[suffixRange])

        guard let frameNum = Int(numStr) else { continue }

        let key = "\(entry.depth)|\(prefix)|\(suffix)|\(numStr.count)"
        entryFrame[idx] = FrameInfo(key: key, frameNum: frameNum)

        if groups[key] == nil {
            groups[key] = GroupInfo(prefix: prefix, suffix: suffix, padding: numStr.count, depth: entry.depth, frames: [])
        }
        groups[key]!.frames.append((frameNum, idx))
    }

    // Build replacement map: for groups that qualify, determine which entries
    // to skip and where to insert the sequence entry (at the first member).
    var skipIndices: Set<Int> = []
    var insertAt: [Int: Entry] = [:]  // entry index -> sequence entry to insert

    for (_, group) in groups {
        if group.frames.count < effectiveMin { continue }

        let sortedFrames = group.frames.sorted { $0.frameNum < $1.frameNum }
        let frameNums = sortedFrames.map(\.frameNum)
        let ranges = findRanges(frameNums)

        // Build a lookup from frameNum to original entry index
        var frameToIdx: [Int: Int] = [:]
        for f in sortedFrames { frameToIdx[f.frameNum] = f.index }

        for r in ranges {
            let indicesInRange = (r.start ... r.end).compactMap { frameToIdx[$0] }
            if r.count >= effectiveMin {
                let pattern = "\(group.prefix)[\(String(format: "%0\(group.padding)d", r.start))-\(String(format: "%0\(group.padding)d", r.end))]\(group.suffix)"

                var totalSize: Int64 = 0
                var latestTime = Date.distantPast
                for idx in indicesInRange {
                    let entry = manifest.entries[idx]
                    totalSize += entry.size
                    if entry.timestamp > latestTime { latestTime = entry.timestamp }
                }

                let firstEntry = manifest.entries[indicesInRange.min()!]
                let seqEntry = Entry(
                    mode: firstEntry.mode,
                    timestamp: latestTime,
                    size: totalSize,
                    name: pattern,
                    depth: group.depth,
                    isSequence: true,
                    pattern: pattern
                )

                // Insert sequence entry at the position of the first member
                let firstIdx = indicesInRange.min()!
                insertAt[firstIdx] = seqEntry
                for idx in indicesInRange { skipIndices.insert(idx) }
            }
        }
    }

    // Second pass: emit entries in original order, replacing sequences in-place.
    var result = Manifest(version: manifest.version)
    for (idx, entry) in manifest.entries.enumerated() {
        if let seqEntry = insertAt[idx] {
            result.addEntry(seqEntry)
        }
        if skipIndices.contains(idx) { continue }
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
