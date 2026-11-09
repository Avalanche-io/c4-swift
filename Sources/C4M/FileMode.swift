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

    // MARK: - Null and known zero

    /// Null / unspecified mode, written `-`. The raw value 0 means "not
    /// yet checked", never "checked and found zero" (see `zero`).
    public static let null = FileMode(rawValue: 0)

    /// The known-zero sentinel bit. No operating system mode sets bit 18,
    /// and `typeMask` and `permissions` both ignore it, so a mode carrying
    /// it behaves as mode 0 everywhere a mode is applied while remaining
    /// distinct from `null`. Mirrors the Go library's `c4m.ZeroMode`.
    public static let zeroFlag = FileMode(rawValue: 1 << 18)

    /// The known zero mode: a regular file with no permission bits,
    /// written `----------`. Not the null mode: null means the mode was
    /// never observed; zero means it was observed and found to be zero.
    public static let zero = zeroFlag

    /// A mode observed on disk or parsed from a ten-character string is
    /// known, never null: an all-zero mode becomes `zero`.
    public static func known(_ m: FileMode) -> FileMode {
        m.rawValue == 0 ? zero : m
    }

    // MARK: - Common presets

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
    public var isRegular: Bool { rawValue & Self.typeMask.rawValue == Self.typeRegular.rawValue && !isNull }
    public var isNamedPipe: Bool { rawValue & Self.typeMask.rawValue == Self.typeNamedPipe.rawValue }
    public var isSocket: Bool { rawValue & Self.typeMask.rawValue == Self.typeSocket.rawValue }
    public var isBlock: Bool { rawValue & Self.typeMask.rawValue == Self.typeBlock.rawValue }
    public var isChar: Bool { rawValue & Self.typeMask.rawValue == Self.typeChar.rawValue }
    /// True for the null (unspecified) mode, written `-`.
    public var isNull: Bool { rawValue == 0 }

    /// True for the known zero mode, written `----------`: a regular file
    /// with no permission bits. Distinct from `isNull`.
    public var isZero: Bool { rawValue == Self.zero.rawValue }

    /// The 9-bit permission portion (rwxrwxrwx).
    public var permissions: UInt32 { rawValue & 0o0777 }

    // MARK: - Parsing

    /// Parse a mode string: "-" (single dash) is the null mode; any
    /// ten-character Unix mode like "-rw-r--r--" or "drwxr-xr-x" is a known
    /// mode, "----------" included, which is the known zero (`zero`), not null.
    public init?(string s: String) {
        if s == "-" {
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

        // A ten-character mode is always known; all-zero is the known zero, not null.
        self = Self.known(FileMode(rawValue: mode))
    }

    // MARK: - Formatting

    /// The mode as written in a c4m file: "-" for the null mode, otherwise
    /// the 10-character Unix mode string (e.g. "-rw-r--r--"; the known zero
    /// is "----------"). Null is "-" in every form, canonical and pretty.
    public var description: String {
        if isNull { return "-" }

        // The zero sentinel bit is not part of the on-disk mode.
        let rawValue = self.rawValue & ~Self.zeroFlag.rawValue

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
