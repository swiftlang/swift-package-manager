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
