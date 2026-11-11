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
            // Integers of any length, with no parse: an Int64 wraps (or
            // traps) at 20 digits, and two different runs must never tie.
            let c = compareDigitRuns(sa.text, sb.text)
            if c != 0 {
                return c < 0
            }
        } else if sa.isNumeric != sb.isNumeric {
            // Text sorts before numeric (per spec)
            return !sa.isNumeric
        } else {
            // Both text: UTF-8 byte comparison, as Go's. Swift String
            // comparison treats the NFC and NFD spellings as equal, which
            // left their order to chance (unicode-name vector).
            if !sameBytes(sa.text, sb.text) {
                return Array(sa.text.utf8).lexicographicallyPrecedes(Array(sb.text.utf8))
            }
        }
    }

    return segsA.count < segsB.count
}

// MARK: - Internal

private struct Segment {
    let text: String
    let isNumeric: Bool
}

/// Orders two runs of ASCII digits by integer value of any length:
/// leading zeros dropped, a shorter remainder is the smaller value, equal
/// lengths compare digit by digit, and equal values put the shorter
/// spelling first ("1" < "01"). Returns -1, 0 or 1.
private func compareDigitRuns(_ a: String, _ b: String) -> Int {
    let ta = a.drop(while: { $0 == "0" })
    let tb = b.drop(while: { $0 == "0" })
    if ta.count != tb.count { return ta.count < tb.count ? -1 : 1 }
    if ta != tb { return ta < tb ? -1 : 1 }
    if a.count != b.count { return a.count < b.count ? -1 : 1 }
    return 0
}

private func segmentString(_ s: String) -> [Segment] {
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
            segments.append(Segment(text: current, isNumeric: isNumeric))
            current = String(ch)
            isNumeric = isDigit
        } else {
            current.append(ch)
        }
    }

    if !current.isEmpty {
        segments.append(Segment(text: current, isNumeric: isNumeric))
    }

    return segments
}
