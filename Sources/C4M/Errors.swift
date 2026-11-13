import Foundation

/// Errors that can occur during C4M parsing and validation.
public enum C4MError: Error, Sendable, CustomStringConvertible {
    case invalidEntry(Int, String)
    case duplicatePath(String)
    case pathTraversal(String)
    case notSupported(String)
    case patchIDMismatch
    /// Reserved for API stability; the decoder no longer reports it.
    /// Consecutive checkpoints are legal (chain-grammar erratum
    /// 2026-07-13), and a bare C4 ID at EOF is `trailingID`.
    case emptyPatch
    /// The stream ends with a bare C4 ID, on the given line. A c4m file
    /// never ends with its own ID: a bare ID is a boundary before a
    /// patch, and a file that ends with one is a format error (ruled
    /// 2026-11-08). Files written by c4 1.0.13 through 1.0.26 with
    /// `c4 diff >>` have this shape; `c4 id FILE.c4m` (c4 1.1) rewrites
    /// them.
    case trailingID(Int)
    case invalidFlowTarget(String)

    public var description: String {
        switch self {
        case .invalidEntry(let line, let msg): return "c4m: line \(line): \(msg)"
        case .duplicatePath(let p): return "c4m: duplicate path: \(p)"
        case .pathTraversal(let p): return "c4m: path traversal: \(p)"
        case .notSupported(let f): return "c4m: not supported: \(f)"
        case .patchIDMismatch: return "c4m: patch ID does not match prior content"
        case .emptyPatch: return "c4m: empty patch section"
        case .trailingID(let line):
            return "c4m: a bare C4 ID ends the file; a c4m file never ends with its own ID (line \(line)): delete that line, or rewrite the file with `c4 id FILE.c4m > fixed.c4m`"
        case .invalidFlowTarget(let t): return "c4m: invalid flow target: \(t)"
        }
    }
}
