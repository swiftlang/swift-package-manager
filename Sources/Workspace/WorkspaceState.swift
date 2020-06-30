/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import PackageGraph
import PackageModel
import SourceControl
import TSCUtility

/// An individual managed dependency.
///
/// Each dependency will have a checkout containing the sources at a
/// particular revision, and may have an associated version.
public final class ManagedDependency {

    /// Represents the state of the managed dependency.
    public enum State: Equatable {

        /// The dependency is a managed checkout.
        case checkout(CheckoutState)

        /// The dependency is in edited state.
        ///
        /// If the path is non-nil, the dependency is managed by a user and is
        /// located at the path. In other words, this dependency is being used
        /// for top of the tree style development.
        case edited(AbsolutePath?)

        // The dependency is a local package.
        case local

        /// Returns true if state is checkout.
        var isCheckout: Bool {
            if case .checkout = self { return true }
            return false
        }
    }

    /// The package reference.
    public let packageRef: PackageReference

    /// The state of the managed dependency.
    public let state: State

    /// The checked out path of the dependency on disk, relative to the workspace checkouts path.
    public let subpath: RelativePath

    /// A dependency which in editable state is based on a dependency from
    /// which it edited from.
    ///
    /// This information is useful so it can be restored when users
    /// unedit a package.
    public internal(set) var basedOn: ManagedDependency?

    public init(
        packageRef: PackageReference,
        subpath: RelativePath,
        checkoutState: CheckoutState
    ) {
        self.packageRef = packageRef
        self.state = .checkout(checkoutState)
        self.basedOn = nil
        self.subpath = subpath
    }

    /// Create a dependency present locally on the filesystem.
    public static func local(
        packageRef: PackageReference
    ) -> ManagedDependency {
        return ManagedDependency(
            packageRef: packageRef,
            state: .local,
            // FIXME: This is just a fake entry, we should fix it.
            subpath: RelativePath(packageRef.identity),
            basedOn: nil
        )
    }

    private init(
        packageRef: PackageReference,
        state: State,
        subpath: RelativePath,
        basedOn: ManagedDependency?
    ) {
        self.packageRef = packageRef
        self.subpath = subpath
        self.basedOn = basedOn
        self.state = state
    }

    private init(
        basedOn dependency: ManagedDependency,
        subpath: RelativePath,
        unmanagedPath: AbsolutePath?
    ) {
        assert(dependency.state.isCheckout)
        self.basedOn = dependency
        self.packageRef = dependency.packageRef
        self.subpath = subpath
        self.state = .edited(unmanagedPath)
    }

    /// Create an editable managed dependency based on a dependency which
    /// was *not* in edit state.
    ///
    /// - Parameters:
    ///     - subpath: The subpath inside the editables directory.
    ///     - unmanagedPath: A custom absolute path instead of the subpath.
    public func editedDependency(subpath: RelativePath, unmanagedPath: AbsolutePath?) -> ManagedDependency {
        return ManagedDependency(basedOn: self, subpath: subpath, unmanagedPath: unmanagedPath)
    }

    /// Returns true if the dependency is edited.
    public var isEdited: Bool {
        switch state {
        case .checkout, .local:
            return false
        case .edited:
            return true
        }
    }
}

/// A downloaded artifact managed by the workspace.
public final class ManagedArtifact {

    /// Represents the source of the artifact.
    public enum Source: Equatable {

        /// Represents a remote artifact, with the url it was downloaded from, its checksum, and its path relative to
        /// the workspace artifacts path.
        case remote(url: String, checksum: String, subpath: RelativePath)

        /// Represents a locally available artifact, with its path relative to its package.
        case local(path: String)
    }

    /// The package reference.
    public let packageRef: PackageReference

    /// The name of the binary target the artifact corresponds to.
    public let targetName: String

    /// The source of the artifact (local or remote).
    public let source: Source

    public init(
        packageRef: PackageReference,
        targetName: String,
        source: Source
    ) {
        self.packageRef = packageRef
        self.targetName = targetName
        self.source = source
    }

    /// Create an artifact downloaded from a remote url.
    public static func remote(
        packageRef: PackageReference,
        targetName: String,
        url: String,
        checksum: String,
        subpath: RelativePath
    ) -> ManagedArtifact {
        return ManagedArtifact(
            packageRef: packageRef,
            targetName: targetName,
            source: .remote(url: url, checksum: checksum, subpath: subpath)
        )
    }

    /// Create an artifact present locally on the filesystem.
    public static func local(
        packageRef: PackageReference,
        targetName: String,
        path: String
    ) -> ManagedArtifact {
        return ManagedArtifact(
            packageRef: packageRef,
            targetName: targetName,
            source: .local(path: path)
        )
    }
}

/// Represents the workspace internal state persisted on disk.
public final class WorkspaceState: SimplePersistanceProtocol {

    /// The schema version of the resolved file.
    ///
    /// * 4: Artifacts.
    /// * 3: Package kind.
    /// * 2: Package identity.
    /// * 1: Initial version.
    static let schemaVersion: Int = 4

    /// The dependencies managed by the Workspace.
    public private(set) var dependencies: ManagedDependencies

    /// The artifacts managed by the Workspace.
    public private(set) var artifacts: ManagedArtifacts

    /// Path to the state file.
    public let path: AbsolutePath

    /// persistence helper
    let persistence: SimplePersistence

    init(dataPath: AbsolutePath, fileSystem: FileSystem) {
        let statePath = dataPath.appending(component: "workspace-state.json")

        self.dependencies = ManagedDependencies()
        self.artifacts = ManagedArtifacts()
        self.path = statePath
        self.persistence = SimplePersistence(
            fileSystem: fileSystem,
            schemaVersion: WorkspaceState.schemaVersion,
            supportedSchemaVersions: [2, 3],
            statePath: statePath,
            otherStatePaths: [dataPath.appending(component: "dependencies-state.json")]
        )

        // Load the state from disk, if possible.
        //
        // If the disk operation here fails, we ignore the error here.
        // This means if managed dependencies data is corrupted or out of date,
        // clients will not see the old data and managed dependencies will be
        // reset.  However there could be other errors, like permission issues,
        // these errors will also be ignored but will surface when clients try
        // to save the state.
        do {
            try self.persistence.restoreState(self)
        } catch {
            // FIXME: We should emit a warning here using the diagnostic engine.
            print("\(error)")
        }
    }

    func reset() throws {
        dependencies = ManagedDependencies()
        artifacts = ManagedArtifacts()
        try saveState()
    }

    public func saveState() throws {
        try self.persistence.saveState(self)
    }

    /// Returns true if the state file exists on the filesystem.
    public func stateFileExists() -> Bool {
        return persistence.stateFileExists()
    }

    public func restore(from json: JSON) throws {
        try restore(from: json, supportedSchemaVersion: WorkspaceState.schemaVersion)
    }

    public func restore(from json: JSON, supportedSchemaVersion: Int) throws {
        dependencies = try ManagedDependencies(json: json.get("dependencies"))

        if supportedSchemaVersion >= 4 {
            artifacts = try ManagedArtifacts(json: json.get("artifacts"))
        }
    }

    public func toJSON() -> JSON {
        return JSON([
            "dependencies": dependencies.toJSON(),
            "artifacts": artifacts.toJSON(),
        ])
    }
}

/// A collection of managed dependencies.
public final class ManagedDependencies {

    /// The dependencies keyed by the package URL.
    private var dependencyMap: [String: ManagedDependency]

    fileprivate init(dependencyMap: [String: ManagedDependency] = [:]) {
        self.dependencyMap = dependencyMap
    }

    public subscript(forURL url: String) -> ManagedDependency? {
        dependencyMap[url]
    }

    public subscript(forIdentity identity: String) -> ManagedDependency? {
        dependencyMap.values.first(where: { $0.packageRef.identity == identity })
    }

    public subscript(forNameOrIdentity nameOrIdentity: String) -> ManagedDependency? {
        let lowercasedNameOrIdentity = nameOrIdentity.lowercased()
        return dependencyMap.values.first(where: {
            $0.packageRef.name == nameOrIdentity || $0.packageRef.identity == lowercasedNameOrIdentity
        })
    }

    public func add(_ dependency: ManagedDependency) {
        dependencyMap[dependency.packageRef.path] = dependency
    }

    public func remove(forURL url: String) {
        dependencyMap[url] = nil
    }
}

/// A collection of managed artifacts which have been downloaded.
public final class ManagedArtifacts {

    /// A mapping from package url, to target name, to ManagedArtifact.
    private var artifactMap: [String: [String: ManagedArtifact]]

    private var artifacts: AnyCollection<ManagedArtifact> {
        AnyCollection(artifactMap.values.lazy.flatMap({ $0.values }))
    }

    fileprivate init(artifactMap: [String: [String: ManagedArtifact]] = [:]) {
        self.artifactMap = artifactMap
    }

    public subscript(packageURL packageURL: String, targetName targetName: String) -> ManagedArtifact? {
        artifactMap[packageURL]?[targetName]
    }

    public subscript(packageName packageName: String, targetName targetName: String) -> ManagedArtifact? {
        artifacts.first(where: { $0.packageRef.name == packageName && $0.targetName == targetName })
    }

    public func add(_ artifact: ManagedArtifact) {
        artifactMap[artifact.packageRef.path, default: [:]][artifact.targetName] = artifact
    }

    public func remove(packageURL: String, targetName: String) {
        artifactMap[packageURL]?[targetName] = nil
    }
}

extension ManagedDependency: JSONMappable, JSONSerializable, CustomStringConvertible {
    public convenience init(json: JSON) throws {
        try self.init(
            packageRef: json.get("packageRef"),
            state: json.get("state"),
            subpath: RelativePath(json.get("subpath")),
            basedOn: json.get("basedOn")
        )
    }

    public func toJSON() -> JSON {
        return .init([
            "packageRef": packageRef.toJSON(),
            "subpath": subpath,
            "basedOn": basedOn.toJSON(),
            "state": state
        ])
    }

    public var description: String {
        return "<ManagedDependency: \(packageRef.name) \(state)>"
    }
}


extension ManagedDependency.State: JSONMappable, JSONSerializable {
    public func toJSON() -> JSON {
        switch self {
        case .checkout(let checkoutState):
            return .init([
                "name": "checkout",
                "checkoutState": checkoutState,
            ])
        case .edited(let path):
            return .init([
                "name": "edited",
                "path": path.toJSON(),
            ])
        case .local:
            return .init([
                "name": "local",
            ])
        }
    }

    public init(json: JSON) throws {
        let name: String = try json.get("name")
        switch name {
        case "checkout":
            self = try .checkout(json.get("checkoutState"))
        case "edited":
            let path: String? = json.get("path")
            self = .edited(path.map({AbsolutePath($0)}))
        case "local":
            self = .local
        default:
            throw JSON.MapError.custom(key: nil, message: "Invalid state \(name)")
        }
    }

    public var description: String {
        switch self {
        case .checkout(let checkout):
            return "\(checkout)"
        case .edited:
            return "edited"
        case .local:
            return "local"
        }
    }
}

extension ManagedArtifact: JSONMappable, JSONSerializable, CustomStringConvertible {
    public convenience init(json: JSON) throws {
        try self.init(
            packageRef: json.get("packageRef"),
            targetName: json.get("targetName"),
            source: json.get("source")
        )
    }

    public func toJSON() -> JSON {
        return .init([
            "packageRef": packageRef,
            "targetName": targetName,
            "source": source,
        ])
    }

    public var description: String {
        return "<ManagedArtifact: \(packageRef.name).\(targetName) \(source)>"
    }
}

extension ManagedArtifact.Source: JSONMappable, JSONSerializable, CustomStringConvertible {
    public init(json: JSON) throws {
        let type: String = try json.get("type")
        switch type {
        case "local":
            self = try .local(path: json.get("path"))
        case "remote":
            let url: String = try json.get("url")
            let checksum: String = try json.get("checksum")
            let subpath = try RelativePath(json.get("subpath"))
            self = .remote(url: url, checksum: checksum, subpath: subpath)
        default:
            throw JSON.MapError.custom(key: nil, message: "Invalid type \(type)")
        }
    }

    public func toJSON() -> JSON {
        switch self {
        case .local(let path):
            return .init([
                "type": "local",
                "path": path,
            ])
        case .remote(let url, let checksum, let subpath):
            return .init([
                "type": "remote",
                "url": url,
                "checksum": checksum,
                "subpath": subpath.toJSON(),
            ])
        }
    }

    public var description: String {
        switch self {
        case .local(let path):
            return "local(path: \(path))"
        case .remote(let url, let checksum, let subpath):
            return "remote(url: \(url), checksum: \(checksum), subpath: \(subpath))"
        }
    }
}

extension ManagedDependencies: Collection {
    public typealias Index = Dictionary<String, ManagedDependency>.Index
    public typealias Element = ManagedDependency

    public var startIndex: Index {
        dependencyMap.startIndex
    }

    public var endIndex: Index {
        dependencyMap.endIndex
    }

    public subscript(index: Index) -> Element {
        dependencyMap[index].value
    }

    public func index(after index: Index) -> Index {
        dependencyMap.index(after: index)
    }
}

extension ManagedDependencies: JSONMappable, JSONSerializable {
    public convenience init(json: JSON) throws {
        let dependencies = try Array<ManagedDependency>(json: json)
        let dependencyMap = Dictionary(uniqueKeysWithValues: dependencies.lazy.map({ ($0.packageRef.path, $0) }))
        self.init(dependencyMap: dependencyMap)
    }

    public func toJSON() -> JSON {
        dependencyMap.values.toJSON()
    }
}

extension ManagedDependencies: CustomStringConvertible {
    public var description: String {
        "<ManagedDependencies: \(Array(dependencyMap.values))>"
    }
}

extension ManagedArtifacts: Collection {
    public var startIndex: AnyIndex {
        artifacts.startIndex
    }

    public var endIndex: AnyIndex {
        artifacts.endIndex
    }

    public subscript(index: AnyIndex) -> ManagedArtifact {
        artifacts[index]
    }

    public func index(after index: AnyIndex) -> AnyIndex {
        artifacts.index(after: index)
    }
}

extension ManagedArtifacts: JSONMappable, JSONSerializable {
    public convenience init(json: JSON) throws {
        let artifacts = try Array<ManagedArtifact>(json: json)
        let artifactsByPackagePath = Dictionary(grouping: artifacts, by: { $0.packageRef.path })
        let artifactMap = artifactsByPackagePath.mapValues({ artifacts in
            Dictionary(uniqueKeysWithValues: artifacts.lazy.map({ ($0.targetName, $0) }))
        })
        self.init(artifactMap: artifactMap)
    }

    public func toJSON() -> JSON {
        artifacts.toJSON()
    }
}

extension ManagedArtifacts: CustomStringConvertible {
    public var description: String {
        "<ManagedArtifacts: \(Array(artifacts))>"
    }
}
