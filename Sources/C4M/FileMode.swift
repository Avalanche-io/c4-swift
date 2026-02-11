import Foundation

/// Unix file mode (type + permission bits) as used in C4M manifests.
public struct FileMode: Sendable, Hashable, Codable, CustomStringConvertible, RawRepresentable {

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // MARK: - Type bits (stored in the top 4 bits of the 16-bit mode)

    /// Bit mask for the file-type portion.
    public static let typeMask   = FileMode(rawValue: 0xF000)

    public static let typeRegular   = FileMode(rawValue: 0x0000)
    public static let typeDir       = FileMode(rawValue: 0x4000)
    public static let typeSymlink   = FileMode(rawValue: 0xA000)
    public static let typeNamedPipe = FileMode(rawValue: 0x1000)
    public static let typeSocket    = FileMode(rawValue: 0xC000)
    public static let typeBlock     = FileMode(rawValue: 0x6000)
    public static let typeChar      = FileMode(rawValue: 0x2000)

    // MARK: - Special bits

    public static let setuid  = FileMode(rawValue: 0x0800)
    public static let setgid  = FileMode(rawValue: 0x0400)
    public static let sticky  = FileMode(rawValue: 0x0200)

    // MARK: - Permission bits

    public static let ownerRead    = FileMode(rawValue: 0o0400)
    public static let ownerWrite   = FileMode(rawValue: 0o0200)
    public static let ownerExec    = FileMode(rawValue: 0o0100)
    public static let groupRead    = FileMode(rawValue: 0o0040)
    public static let groupWrite   = FileMode(rawValue: 0o0020)
    public static let groupExec    = FileMode(rawValue: 0o0010)
    public static let otherRead    = FileMode(rawValue: 0o0004)
    public static let otherWrite   = FileMode(rawValue: 0o0002)
    public static let otherExec    = FileMode(rawValue: 0o0001)

    // MARK: - Common presets

    /// Null / unspecified mode.
    public static let null = FileMode(rawValue: 0)

    /// `-rw-r--r--` (0644)
    public static let file644 = FileMode(rawValue: 0o0644)

    /// `-rwxr-xr-x` (0755)
    public static let file755 = FileMode(rawValue: 0o0755)

    /// `drwxr-xr-x`
    public static let dir755 = FileMode(rawValue: 0x4000 | 0o0755)

    /// `lrwxrwxrwx`
    public static let symlink777 = FileMode(rawValue: 0xA000 | 0o0777)

    // MARK: - Queries

    public var isDir: Bool { rawValue & Self.typeMask.rawValue == Self.typeDir.rawValue }
    public var isSymlink: Bool { rawValue & Self.typeMask.rawValue == Self.typeSymlink.rawValue }
    public var isRegular: Bool { rawValue & Self.typeMask.rawValue == Self.typeRegular.rawValue && rawValue != 0 }
    public var isNamedPipe: Bool { rawValue & Self.typeMask.rawValue == Self.typeNamedPipe.rawValue }
    public var isSocket: Bool { rawValue & Self.typeMask.rawValue == Self.typeSocket.rawValue }
    public var isBlock: Bool { rawValue & Self.typeMask.rawValue == Self.typeBlock.rawValue }
    public var isChar: Bool { rawValue & Self.typeMask.rawValue == Self.typeChar.rawValue }
    public var isNull: Bool { rawValue == 0 }

    /// The 9-bit permission portion (rwxrwxrwx).
    public var permissions: UInt32 { rawValue & 0o0777 }

    // MARK: - Parsing

    /// Parse a 10-character Unix mode string like "-rw-r--r--" or "drwxr-xr-x".
    /// Accepts "-" (single dash) and "----------" as null mode.
    public init?(string s: String) {
        if s == "-" || s == "----------" {
            self.rawValue = 0
            return
        }
        guard s.count == 10 else { return nil }
        let chars = Array(s)

        var mode: UInt32 = 0

        // File type (first character)
        switch chars[0] {
        case "-": break // regular
        case "d": mode |= Self.typeDir.rawValue
        case "l": mode |= Self.typeSymlink.rawValue
        case "p": mode |= Self.typeNamedPipe.rawValue
        case "s": mode |= Self.typeSocket.rawValue
        case "b": mode |= Self.typeBlock.rawValue
        case "c": mode |= Self.typeChar.rawValue
        default: return nil
        }

        // Permission characters: rwxrwxrwx at positions 1-9
        let permBits: [UInt32] = [0o400, 0o200, 0o100, 0o040, 0o020, 0o010, 0o004, 0o002, 0o001]
        let permChars: [Character] = ["r", "w", "x", "r", "w", "x", "r", "w", "x"]

        for i in 0 ..< 9 {
            let c = chars[i + 1]
            let expected = permChars[i]
            if c == expected {
                mode |= permBits[i]
            } else if c == "-" {
                // no permission
            } else if i == 2 && (c == "s" || c == "S") {
                // setuid
                mode |= Self.setuid.rawValue
                if c == "s" { mode |= permBits[i] }
            } else if i == 5 && (c == "s" || c == "S") {
                // setgid
                mode |= Self.setgid.rawValue
                if c == "s" { mode |= permBits[i] }
            } else if i == 8 && (c == "t" || c == "T") {
                // sticky
                mode |= Self.sticky.rawValue
                if c == "t" { mode |= permBits[i] }
            } else {
                return nil
            }
        }

        self.rawValue = mode
    }

    // MARK: - Formatting

    /// The 10-character Unix mode string (e.g. "-rw-r--r--").
    public var description: String {
        if rawValue == 0 { return "----------" }

        var buf: [Character] = Array(repeating: "-", count: 10)

        // File type
        let typeVal = rawValue & Self.typeMask.rawValue
        switch typeVal {
        case Self.typeDir.rawValue:       buf[0] = "d"
        case Self.typeSymlink.rawValue:   buf[0] = "l"
        case Self.typeNamedPipe.rawValue: buf[0] = "p"
        case Self.typeSocket.rawValue:    buf[0] = "s"
        case Self.typeBlock.rawValue:     buf[0] = "b"
        case Self.typeChar.rawValue:      buf[0] = "c"
        default:                          buf[0] = "-"
        }

        // Permission bits
        let rwx: [Character] = ["r", "w", "x", "r", "w", "x", "r", "w", "x"]
        let bits: [UInt32] = [0o400, 0o200, 0o100, 0o040, 0o020, 0o010, 0o004, 0o002, 0o001]
        for i in 0 ..< 9 {
            if rawValue & bits[i] != 0 {
                buf[i + 1] = rwx[i]
            }
        }

        // Special bits
        if rawValue & Self.setuid.rawValue != 0 {
            buf[3] = buf[3] == "x" ? "s" : "S"
        }
        if rawValue & Self.setgid.rawValue != 0 {
            buf[6] = buf[6] == "x" ? "s" : "S"
        }
        if rawValue & Self.sticky.rawValue != 0 {
            buf[9] = buf[9] == "x" ? "t" : "T"
        }

        return String(buf)
    }
}
