import Foundation

/// Encode a raw filesystem name using the Universal Filename Encoding
/// (three-tier system). The result contains only printable UTF-8 characters,
/// with Tier 2 backslash escapes for common control chars and Tier 3 braille
/// encoding for all other non-printable bytes.
public func safeName(_ raw: String) -> String {
    // Fast path: no scalar needs encoding. A Swift String is always valid
    // UTF-8, and every ASCII control byte is a scalar the table calls
    // unprintable, so this one pass covers every byte.
    let needsEncoding = raw.unicodeScalars.contains {
        $0 == "\u{00A4}" || $0 == "\\" || !isPrintableScalar($0)
    }
    if !needsEncoding {
        return raw
    }

    var result = ""
    var pending: [UInt8] = [] // Tier 3 accumulator

    func flushPending() {
        if pending.isEmpty { return }
        result.append("\u{00A4}")
        for byte in pending {
            result.append(Character(Unicode.Scalar(0x2800 + Int(byte))!))
        }
        result.append("\u{00A4}")
        pending.removeAll()
    }

    for scalar in raw.unicodeScalars {
        // Tier 1: printable UTF-8, not currency sign, not backslash
        if isPrintableScalar(scalar) && scalar != "\u{00A4}" && scalar != "\\" {
            flushPending()
            result.append(Character(scalar))
            continue
        }

        // Tier 2: backslash escapes for specific characters
        if let esc = tier2Escape(scalar) {
            flushPending()
            result.append("\\")
            result.append(Character(Unicode.Scalar(esc)))
            continue
        }

        // Tier 3: accumulate bytes for braille encoding
        var utf8Bytes = [UInt8]()
        UTF8.encode(scalar) { utf8Bytes.append($0) }
        pending.append(contentsOf: utf8Bytes)
    }
    flushPending()

    return result
}

/// Reverse SafeName: decode Tier 2 backslash escapes and Tier 3 braille
/// patterns back to raw bytes.
///
/// A Swift String cannot hold bytes that are not UTF-8, which Tier 3 can
/// carry. For such a name this returns `encoded` itself, a different name;
/// the decoder uses `unsafeNameExact` and refuses the line instead.
public func unsafeName(_ encoded: String) -> String {
    unsafeNameExact(encoded) ?? encoded
}

/// Reverse SafeName exactly: the decoded name, or nil when its bytes are not
/// UTF-8 and so cannot be held in a String (SafeName vector).
func unsafeNameExact(_ encoded: String) -> String? {
    if !encoded.contains("\u{00A4}") && !encoded.contains("\\") {
        return encoded
    }

    var result: [UInt8] = []
    let scalars = Array(encoded.unicodeScalars)
    var i = 0

    while i < scalars.count {
        let scalar = scalars[i]

        // Tier 2: backslash escape
        if scalar == "\\" && i + 1 < scalars.count {
            if let val = tier2Unescape(scalars[i + 1]) {
                result.append(val)
                i += 2
                continue
            }
            // Lone backslash or unknown escape - pass through
            result.append(contentsOf: Array("\\".utf8))
            i += 1
            continue
        }

        // Tier 3: currency sign delimited braille range
        if scalar == "\u{00A4}" {
            var j = i + 1
            var decoded = false
            var brailleBytes: [UInt8] = []
            while j < scalars.count {
                let br = scalars[j]
                if br == "\u{00A4}" {
                    if decoded {
                        result.append(contentsOf: brailleBytes)
                        i = j + 1
                        break
                    } else {
                        // Empty currency sign pair or lone currency sign
                        var utf8Bytes = [UInt8]()
                        UTF8.encode(scalar) { utf8Bytes.append($0) }
                        result.append(contentsOf: utf8Bytes)
                        i += 1
                        break
                    }
                }
                if br.value >= 0x2800 && br.value <= 0x28FF {
                    brailleBytes.append(UInt8(br.value - 0x2800))
                    decoded = true
                    j += 1
                    continue
                }
                break
            }
            if j >= scalars.count && decoded {
                // Unterminated braille range - pass through currency sign
                var utf8Bytes = [UInt8]()
                UTF8.encode(scalar) { utf8Bytes.append($0) }
                result.append(contentsOf: utf8Bytes)
                i += 1
            } else if !decoded && j < scalars.count && scalars[j] != "\u{00A4}" {
                var utf8Bytes = [UInt8]()
                UTF8.encode(scalar) { utf8Bytes.append($0) }
                result.append(contentsOf: utf8Bytes)
                i += 1
            }
            continue
        }

        // Tier 1: passthrough
        var utf8Bytes = [UInt8]()
        UTF8.encode(scalar) { utf8Bytes.append($0) }
        result.append(contentsOf: utf8Bytes)
        i += 1
    }

    return String(bytes: result, encoding: .utf8)
}

// MARK: - Internal Helpers

/// Whether SafeName writes a scalar as itself (Tier 1): Go's unicode.IsPrint
/// pinned to one Unicode version (`printableRanges`, generated from the
/// shared printable-<version>.txt by Scripts/gen_printable.swift), never the
/// runtime's Unicode tables, so a name's encoding, and so its C4 ID, is the
/// same on every runtime (decided 2026-11-13 by the release lead;
/// reversible). Through 2026-11-13 this passed every scalar except the C0
/// and C1 controls, so 13 names in the shared SafeName vector (non-ASCII
/// spaces, format characters, private use, unassigned, noncharacters) were
/// written raw where Go encodes them.
func isPrintableScalar(_ scalar: Unicode.Scalar) -> Bool {
    let v = scalar.value
    var lo = 0
    var hi = printableRanges.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if v < printableRanges[mid].0 {
            hi = mid
        } else if v > printableRanges[mid].1 {
            lo = mid + 1
        } else {
            return true
        }
    }
    return false
}

/// Return the Tier 2 escape character for a Unicode scalar, or nil.
private func tier2Escape(_ scalar: Unicode.Scalar) -> UInt8? {
    switch scalar.value {
    case 0x00: return UInt8(ascii: "0")
    case 0x09: return UInt8(ascii: "t")
    case 0x0A: return UInt8(ascii: "n")
    case 0x0D: return UInt8(ascii: "r")
    case 0x5C: return UInt8(ascii: "\\")  // backslash
    default: return nil
    }
}

/// Return the byte value for a Tier 2 escape character, or nil.
private func tier2Unescape(_ scalar: Unicode.Scalar) -> UInt8? {
    switch scalar {
    case "0": return 0x00
    case "t": return 0x09
    case "n": return 0x0A
    case "r": return 0x0D
    case "\\": return 0x5C
    default: return nil
    }
}
