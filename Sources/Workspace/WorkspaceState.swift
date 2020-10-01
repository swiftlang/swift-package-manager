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
