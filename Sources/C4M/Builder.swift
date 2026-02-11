import Foundation

/// Fluent API for constructing C4M manifests programmatically.
public final class ManifestBuilder: @unchecked Sendable {

    private var manifest: Manifest
    private var layerBy: String = ""
    private var layerNote: String = ""
    private var layerTime: Date?
    private var removals: [String] = []

    public init() {
        self.manifest = Manifest()
    }

    public init(manifest: Manifest) {
        self.manifest = manifest
    }

    // MARK: - Configuration

    /// Set the base manifest ID.
    @discardableResult
    public func withBaseID(_ id: C4ID) -> ManifestBuilder {
        manifest.base = id
        return self
    }

    /// Set the author for layer metadata.
    @discardableResult
    public func by(_ author: String) -> ManifestBuilder {
        layerBy = author
        return self
    }

    /// Set the note for layer metadata.
    @discardableResult
    public func note(_ note: String) -> ManifestBuilder {
        layerNote = note
        return self
    }

    /// Set the timestamp for layer metadata.
    @discardableResult
    public func at(_ timestamp: Date) -> ManifestBuilder {
        layerTime = timestamp
        return self
    }

    /// Queue a path for removal.
    @discardableResult
    public func remove(_ path: String) -> ManifestBuilder {
        removals.append(path)
        return self
    }

    /// Queue a directory for removal (ensures trailing slash).
    @discardableResult
    public func removeDir(_ path: String) -> ManifestBuilder {
        let p = path.hasSuffix("/") ? path : path + "/"
        removals.append(p)
        return self
    }

    // MARK: - Adding Entries

    /// Add a file at the root level.
    @discardableResult
    public func addFile(
        _ name: String,
        mode: FileMode = .file644,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        size: Int64 = 0,
        c4id: C4ID = .void
    ) -> ManifestBuilder {
        manifest.addEntry(Entry(
            mode: mode,
            timestamp: timestamp,
            size: size,
            name: name,
            c4id: c4id,
            depth: 0
        ))
        return self
    }

    /// Add a directory at the root level and return a DirBuilder for adding children.
    public func addDir(
        _ name: String,
        mode: FileMode = .dir755,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        size: Int64 = 0,
        c4id: C4ID = .void
    ) -> DirBuilder {
        let dirName = name.hasSuffix("/") ? name : name + "/"
        let entry = Entry(
            mode: mode,
            timestamp: timestamp,
            size: size,
            name: dirName,
            c4id: c4id,
            depth: 0
        )
        manifest.addEntry(entry)
        return DirBuilder(root: self, parentDepth: 0)
    }

    // MARK: - Build

    /// Construct the manifest.
    public func build() -> Manifest {
        if !removals.isEmpty {
            let layer = Layer(type: .remove, by: layerBy, time: layerTime, note: layerNote)
            manifest.layers.append(layer)
            for path in removals {
                manifest.addEntry(Entry(name: path, depth: 0, inRemoveLayer: true))
            }
        }
        return manifest
    }

    // MARK: - Internal

    fileprivate func appendEntry(_ entry: Entry) {
        manifest.addEntry(entry)
    }
}

/// Fluent builder for directory contents.
public final class DirBuilder: @unchecked Sendable {

    private let root: ManifestBuilder
    private let parentDepth: Int
    private var parent: DirBuilder?

    init(root: ManifestBuilder, parentDepth: Int, parent: DirBuilder? = nil) {
        self.root = root
        self.parentDepth = parentDepth
        self.parent = parent
    }

    /// Add a file as a child of this directory.
    @discardableResult
    public func addFile(
        _ name: String,
        mode: FileMode = .file644,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        size: Int64 = 0,
        c4id: C4ID = .void
    ) -> DirBuilder {
        root.appendEntry(Entry(
            mode: mode,
            timestamp: timestamp,
            size: size,
            name: name,
            c4id: c4id,
            depth: parentDepth + 1
        ))
        return self
    }

    /// Add a subdirectory and return a builder for it.
    public func addDir(
        _ name: String,
        mode: FileMode = .dir755,
        timestamp: Date = Date(timeIntervalSince1970: 0),
        size: Int64 = 0,
        c4id: C4ID = .void
    ) -> DirBuilder {
        let dirName = name.hasSuffix("/") ? name : name + "/"
        root.appendEntry(Entry(
            mode: mode,
            timestamp: timestamp,
            size: size,
            name: dirName,
            c4id: c4id,
            depth: parentDepth + 1
        ))
        return DirBuilder(root: root, parentDepth: parentDepth + 1, parent: self)
    }

    /// Finish this directory and return to the parent ManifestBuilder.
    public func end() -> ManifestBuilder { root }

    /// Finish this subdirectory and return to the parent DirBuilder.
    public func endDir() -> DirBuilder { parent ?? self }
}
