import Foundation

/// Errors that can occur during C4M parsing and validation.
public enum C4MError: Error, Sendable, CustomStringConvertible {
    case invalidEntry(Int, String)
    case duplicatePath(String)
    case pathTraversal(String)
    case notSupported(String)
    case patchIDMismatch
    case emptyPatch
    case invalidFlowTarget(String)

    public var description: String {
        switch self {
        case .invalidEntry(let line, let msg): return "c4m: line \(line): \(msg)"
        case .duplicatePath(let p): return "c4m: duplicate path: \(p)"
        case .pathTraversal(let p): return "c4m: path traversal: \(p)"
        case .notSupported(let f): return "c4m: not supported: \(f)"
        case .patchIDMismatch: return "c4m: patch ID does not match prior content"
        case .emptyPatch: return "c4m: empty patch section"
        case .invalidFlowTarget(let t): return "c4m: invalid flow target: \(t)"
        }
    }
}
