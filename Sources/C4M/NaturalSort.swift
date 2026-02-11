/// Natural sort comparator matching the Go c4m implementation.
///
/// Splits filenames into alternating text/numeric segments and compares:
/// - Numeric segments by integer value; ties broken by shorter representation first.
/// - Mixed types: text sorts before numeric.
/// - Text segments by Unicode codepoint order.
public func naturalLess(_ a: String, _ b: String) -> Bool {
    let segsA = segmentString(a)
    let segsB = segmentString(b)

    let minLen = min(segsA.count, segsB.count)
    for i in 0 ..< minLen {
        let sa = segsA[i]
        let sb = segsB[i]

        if sa.isNumeric && sb.isNumeric {
            if sa.numValue != sb.numValue {
                return sa.numValue < sb.numValue
            }
            if sa.text.count != sb.text.count {
                return sa.text.count < sb.text.count
            }
        } else if sa.isNumeric != sb.isNumeric {
            // Text sorts before numeric (per spec)
            return !sa.isNumeric
        } else {
            // Both text: UTF-8 / codepoint comparison
            if sa.text != sb.text {
                return sa.text < sb.text
            }
        }
    }

    return segsA.count < segsB.count
}

// MARK: - Internal

struct Segment {
    let text: String
    let isNumeric: Bool
    let numValue: Int64
}

func segmentString(_ s: String) -> [Segment] {
    if s.isEmpty { return [] }

    var segments: [Segment] = []
    var current = ""
    var isNumeric = false
    var first = true

    for ch in s {
        let isDigit = ch >= "0" && ch <= "9"

        if first {
            first = false
            isNumeric = isDigit
            current.append(ch)
        } else if isDigit != isNumeric {
            // Transition
            let numVal = isNumeric ? parseNumber(current) : 0
            segments.append(Segment(text: current, isNumeric: isNumeric, numValue: numVal))
            current = String(ch)
            isNumeric = isDigit
        } else {
            current.append(ch)
        }
    }

    if !current.isEmpty {
        let numVal = isNumeric ? parseNumber(current) : 0
        segments.append(Segment(text: current, isNumeric: isNumeric, numValue: numVal))
    }

    return segments
}

private func parseNumber(_ s: String) -> Int64 {
    var result: Int64 = 0
    for ch in s {
        if let d = ch.asciiValue, d >= 0x30 && d <= 0x39 {
            result = result * 10 + Int64(d - 0x30)
        }
    }
    return result
}
