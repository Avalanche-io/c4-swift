import Testing
@testable import C4M

@Suite("FileMode Tests")
struct FileModeTests {

    @Test("Parse regular file 644")
    func parseRegular644() {
        let m = FileMode(string: "-rw-r--r--")
        #expect(m != nil)
        #expect(m!.rawValue == 0o0644)
        #expect(m!.description == "-rw-r--r--")
    }

    @Test("Parse regular file 755")
    func parseRegular755() {
        let m = FileMode(string: "-rwxr-xr-x")
        #expect(m != nil)
        #expect(m!.rawValue == 0o0755)
    }

    @Test("Parse directory")
    func parseDirectory() {
        let m = FileMode(string: "drwxr-xr-x")
        #expect(m != nil)
        #expect(m!.isDir)
        #expect(m!.description == "drwxr-xr-x")
    }

    @Test("Parse symlink")
    func parseSymlink() {
        let m = FileMode(string: "lrwxrwxrwx")
        #expect(m != nil)
        #expect(m!.isSymlink)
        #expect(m!.description == "lrwxrwxrwx")
    }

    @Test("Parse setuid")
    func parseSetuid() {
        let m = FileMode(string: "-rwsr-xr-x")
        #expect(m != nil)
        #expect(m!.rawValue & FileMode.setuid.rawValue != 0)
        #expect(m!.description == "-rwsr-xr-x")
    }

    @Test("Parse setgid")
    func parseSetgid() {
        let m = FileMode(string: "-rwxr-sr-x")
        #expect(m != nil)
        #expect(m!.rawValue & FileMode.setgid.rawValue != 0)
        #expect(m!.description == "-rwxr-sr-x")
    }

    @Test("Parse sticky")
    func parseSticky() {
        let m = FileMode(string: "drwxrwxrwt")
        #expect(m != nil)
        #expect(m!.rawValue & FileMode.sticky.rawValue != 0)
        #expect(m!.description == "drwxrwxrwt")
    }

    @Test("Null mode from single dash")
    func nullModeSingleDash() {
        let m = FileMode(string: "-")
        #expect(m != nil)
        #expect(m!.isNull)
    }

    @Test("Ten dashes is the known zero mode, not null")
    func zeroModeTenDashes() {
        let m = FileMode(string: "----------")
        #expect(m != nil)
        #expect(!m!.isNull)
        #expect(m!.isZero)
        #expect(m == FileMode.zero)
        #expect(m!.isRegular)
        #expect(m!.permissions == 0)
        #expect(m!.description == "----------")
    }

    @Test("Null and zero are distinct values with distinct spellings")
    func nullAndZeroDistinct() {
        #expect(FileMode.null != FileMode.zero)
        #expect(FileMode.null.description == "-")
        #expect(FileMode.zero.description == "----------")
        #expect(FileMode.null.isNull && !FileMode.null.isZero)
        #expect(FileMode.zero.isZero && !FileMode.zero.isNull)
        #expect(!FileMode.null.isRegular)
    }

    @Test("Zero sentinel bit is outside the type mask and permission bits")
    func zeroFlagOutsideMasks() {
        let z = FileMode.zero
        #expect(z.rawValue & FileMode.typeMask.rawValue == 0)
        #expect(z.permissions == 0)
        #expect(z.rawValue & 0o7777 == 0)
        #expect(!z.isDir && !z.isSymlink)
    }

    @Test("known() lifts an all-zero mode to zero and leaves others alone")
    func knownMode() {
        #expect(FileMode.known(FileMode(rawValue: 0)) == FileMode.zero)
        #expect(FileMode.known(.file644) == .file644)
        #expect(FileMode.known(.zero) == .zero)
    }

    @Test("d--------- is a known directory at 0000, not null")
    func zeroPermissionDirectory() {
        let m = FileMode(string: "d---------")
        #expect(m != nil)
        #expect(m!.isDir)
        #expect(!m!.isNull)
        #expect(!m!.isZero)
        #expect(m!.permissions == 0)
        #expect(m!.description == "d---------")
    }

    @Test("Null mode formats as a single dash")
    func nullModeFormats() {
        #expect(FileMode(string: "-")!.description == "-")
    }

    @Test("Invalid mode too short")
    func invalidTooShort() {
        #expect(FileMode(string: "drwxr") == nil)
    }

    @Test("Invalid file type")
    func invalidType() {
        #expect(FileMode(string: "xrwxr-xr-x") == nil)
    }

    @Test("Roundtrip all common modes")
    func roundtripCommonModes() {
        let modes = ["-rw-r--r--", "-rwxr-xr-x", "drwxr-xr-x", "lrwxrwxrwx",
                     "-rwsr-xr-x", "-rwxr-sr-x", "drwxrwxrwt", "----------"]
        for modeStr in modes {
            let m = FileMode(string: modeStr)
            #expect(m != nil, "Failed to parse: \(modeStr)")
            #expect(m!.description == modeStr, "Roundtrip failed: \(modeStr) -> \(m!.description)")
        }
    }

    @Test("Named pipe")
    func namedPipe() {
        let m = FileMode(string: "prw-r--r--")
        #expect(m != nil)
        #expect(m!.isNamedPipe)
        #expect(m!.description == "prw-r--r--")
    }

    @Test("Socket")
    func socket() {
        let m = FileMode(string: "srw-r--r--")
        #expect(m != nil)
        #expect(m!.isSocket)
        #expect(m!.description == "srw-r--r--")
    }
}
