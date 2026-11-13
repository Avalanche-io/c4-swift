// Reads swift-testing's event stream and fails when a test skipped that the
// allow-list does not name, so a test that runs nowhere cannot go unnoticed.
// It prints every skip with the reason the test gave.
//
// Run from the repository root:
//
//     swift test --experimental-event-stream-output events.jsonl \
//                --experimental-event-stream-version 0
//     swift Scripts/skips.swift Scripts/allowed-skips.txt events.jsonl
//
// The event stream, not --xunit-output: swift-testing's JUnit XML writes a
// test cancelled at run time (Test.cancel, Swift 6.3) as a pass, and the
// stream names it. A skip is a testSkipped event (a .disabled or
// .enabled(if:) trait that turned the test or its suite off) or a
// testCancelled or testCaseCancelled event.
//
// The allow-list holds one skip per line: the OS it is allowed on (macos,
// linux, windows, or "*"), then the test ID, with a reason after "#". A test
// ID is the one swift-testing gives, less the source location it appends to
// a function's: C4MTests.SomeSuite/someTest(arg:). A line naming a suite
// allows the suite and every test in it. The checker exits 1 when a skip is
// not listed for this OS, or the stream is empty or cut off; a listed skip
// that did not happen is reported, not failed on.
//
// --os <name> overrides the OS the tests ran on.

import Foundation

#if os(macOS)
var thisOS = "macos"
#elseif os(Linux)
var thisOS = "linux"
#elseif os(Windows)
var thisOS = "windows"
#else
var thisOS = "unknown"
#endif

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("skips: \(msg)\n".utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
if let i = args.firstIndex(of: "--os") {
    guard i + 1 < args.count else { fail("--os needs a name") }
    thisOS = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
guard args.count == 2 else {
    fail("usage: swift Scripts/skips.swift [--os NAME] ALLOW-LIST EVENTS.jsonl")
}

// The skips the list allows on this OS, and every entry, for the report.
var allowed: [String] = []
guard let allowText = try? String(contentsOfFile: args[0], encoding: .utf8) else {
    fail("cannot read \(args[0])")
}
for (n, raw) in allowText.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
    let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    let fields = trimmed.split(separator: " ", maxSplits: 1)
    guard fields.count == 2 else {
        fail("\(args[0]) line \(n + 1): want an OS and a test ID, have \(raw)")
    }
    let os = String(fields[0])
    if os == "*" || os == thisOS {
        allowed.append(fields[1].trimmingCharacters(in: .whitespaces))
    }
}

// stableID drops the "/File.swift:line:column" swift-testing appends to a
// function's ID, so an allow-list line survives an edit above the test.
func stableID(_ id: String) -> String {
    var parts = id.split(separator: "/", omittingEmptySubsequences: false)
    if let last = parts.last {
        let loc = last.split(separator: ":")
        if loc.count == 3, loc[0].hasSuffix(".swift"), Int(loc[1]) != nil, Int(loc[2]) != nil {
            parts.removeLast()
        }
    }
    return parts.joined(separator: "/")
}

// reason is what a skip gave: its comments, else the quoted part of the
// message swift-testing printed.
func reason(_ payload: [String: Any]) -> String {
    if let comments = payload["_comments"] as? [String], !comments.isEmpty {
        return comments.joined(separator: " ")
    }
    let texts = (payload["messages"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
    for t in texts {
        if let open = t.firstIndex(of: "\""), let close = t.lastIndex(of: "\""), open < close {
            return String(t[t.index(after: open)..<close])
        }
    }
    return "no reason given"
}

guard let data = FileManager.default.contents(atPath: args[1]) else {
    print("skips: cannot read \(args[1]): swift test wrote no event stream")
    exit(1)
}
var skips: [String: String] = [:] // stable test ID to reason
var started = false, ended = false, events = 0
for raw in data.split(separator: UInt8(ascii: "\n")) where !raw.isEmpty {
    guard let obj = try? JSONSerialization.jsonObject(with: Data(raw)) as? [String: Any] else {
        print("skips: an event stream line is not JSON: \(String(decoding: raw, as: UTF8.self))")
        exit(1)
    }
    guard obj["kind"] as? String == "event", let p = obj["payload"] as? [String: Any] else { continue }
    events += 1
    switch p["kind"] as? String {
    case "runStarted":
        started = true
    case "runEnded":
        ended = true
    case "testSkipped", "testCancelled", "testCaseCancelled":
        guard let id = p["testID"] as? String else { continue }
        let key = stableID(id)
        if skips[key] == nil {
            skips[key] = (p["kind"] as? String == "testSkipped" ? "" : "cancelled: ") + reason(p)
        }
    default:
        break
    }
}

if events == 0 || !started {
    print("skips: the event stream has no run in it: swift test crashed or never ran")
    exit(1)
}
if !ended {
    print("skips: the run started and never ended: swift test was cut off")
    exit(1)
}

func isAllowed(_ id: String) -> String? {
    allowed.first { id == $0 || id.hasPrefix($0 + "/") }
}

let ids = skips.keys.sorted()
var unlisted: [String] = []
var used = Set<String>()
for id in ids {
    if let entry = isAllowed(id) {
        used.insert(entry)
        print("skips: skipped, allowed on \(thisOS): \(id): \(skips[id]!)")
    } else {
        unlisted.append(id)
    }
}
for id in unlisted {
    print("skips: NOT ALLOWED on \(thisOS): \(id): \(skips[id]!)")
}
print("skips: \(ids.count) tests skipped on \(thisOS), \(ids.count - unlisted.count) of them allowed")
for entry in allowed.sorted() where !used.contains(entry) {
    print("skips: allowed, and it did not skip: \(entry)")
}
exit(unlisted.isEmpty ? 0 : 1)
