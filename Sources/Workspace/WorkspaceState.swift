/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import PackageGraph
import PackageModel
import SourceControl
import TSCBasic

/// Represents the workspace internal state persisted on disk.
public final class WorkspaceState {
    /// The dependencies managed by the Workspace.
    public private(set) var dependencies: ManagedDependencies

    /// The artifacts managed by the Workspace.
    public private(set) var artifacts: Workspace.ManagedArtifacts

    /// Path to the state file.
    public let storagePath: AbsolutePath

    /// storage
    private let storage: WorkspaceStateStorage

    init(dataPath: AbsolutePath, fileSystem: FileSystem) {
        self.storagePath = dataPath.appending(component: "workspace-state.json")
        self.storage = WorkspaceStateStorage(path: self.storagePath, fileSystem: fileSystem)

        // Load the state from disk, if possible.
        //
        // If the disk operation here fails, we ignore the error here.
        // This means if managed dependencies data is corrupted or out of date,
        // clients will not see the old data and managed dependencies will be
        // reset.  However there could be other errors, like permission issues,
        // these errors will also be ignored but will surface when clients try
        // to save the state.
        do {
            let storedState = try self.storage.load()
            self.dependencies = storedState.dependencies
            self.artifacts = storedState.artifacts
        } catch {
            self.dependencies = ManagedDependencies()
            self.artifacts = Workspace.ManagedArtifacts()
            try? self.storage.reset()
            // FIXME: We should emit a warning here using the diagnostic engine.
            TSCBasic.stderrStream.write("warning: unable to restore workspace state: \(error)")
            TSCBasic.stderrStream.flush()
        }
    }

    func reset() throws {
        self.dependencies = ManagedDependencies()
        self.artifacts = Workspace.ManagedArtifacts()
        try self.saveState()
    }

    public func saveState() throws {
        try self.storage.save(dependencies: self.dependencies, artifacts: self.artifacts)
    }

    /// Returns true if the state file exists on the filesystem.
    public func stateFileExists() -> Bool {
        return self.storage.fileExists()
    }
}

// MARK: - Serialization

fileprivate struct WorkspaceStateStorage {
    private let path: AbsolutePath
    private let fileSystem: FileSystem
    private let encoder = JSONEncoder.makeWithDefaults()
    private let decoder = JSONDecoder.makeWithDefaults()

    init(path: AbsolutePath, fileSystem: FileSystem) {
        self.path = path
        self.fileSystem = fileSystem
    }

    func load() throws -> (dependencies: ManagedDependencies, artifacts: Workspace.ManagedArtifacts){
        if !self.fileSystem.exists(self.path) {
            return (dependencies: .init(), artifacts: .init())
        }

        return try self.fileSystem.withLock(on: self.path, type: .shared) {
            let version = try decoder.decode(path: self.path, fileSystem: self.fileSystem, as: Version.self)
            switch version.version {
            case 1,2,3,4:
                let v4 = try self.decoder.decode(path: self.path, fileSystem: self.fileSystem, as: V4.self)
                let dependencyMap = Dictionary(uniqueKeysWithValues: v4.object.dependencies.map{ ($0.packageRef.location, ManagedDependency($0)) })
                let artifacts = v4.object.artifacts.map{ Workspace.ManagedArtifact($0) }
                return (dependencies: .init(dependencyMap: dependencyMap), artifacts: .init(artifacts))
            default:
                throw InternalError("unknown RepositoryManager version: \(version)")
            }
        }
    }

    func save(dependencies: ManagedDependencies, artifacts: Workspace.ManagedArtifacts) throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            try self.fileSystem.createDirectory(self.path.parentDirectory)
        }

        try self.fileSystem.withLock(on: self.path, type: .exclusive) {
            let storage = V4(dependencies: dependencies, artifacts: artifacts)

            let data = try self.encoder.encode(storage)
            try self.fileSystem.writeFileContents(self.path, data: data)
        }
    }

    func reset() throws {
        if !self.fileSystem.exists(self.path.parentDirectory) {
            return
        }
        try self.fileSystem.withLock(on: self.path, type: .exclusive) {
            try self.fileSystem.removeFileTree(self.path)
        }
    }

    func fileExists() -> Bool {
        return self.fileSystem.exists(self.path)
    }

    // version reader
    struct Version: Codable {
        let version: Int
    }

    /// * 4: Artifacts.
    /// * 3: Package kind.
    /// * 2: Package identity.
    /// * 1: Initial version.
    // v4 storage format
    struct V4: Codable {
        let version: Int
        let object: Container

        init (dependencies: ManagedDependencies, artifacts: Workspace.ManagedArtifacts) {
            self.version = 4
            self.object = .init(
                dependencies: dependencies.map { .init($0) },
                artifacts: artifacts.map {.init($0) }
            )
        }

        struct Container: Codable {
            var dependencies: [Dependency]
            var artifacts: [Artifact]
        }

        final class Dependency: Codable {
            let packageRef: PackageReference
            let state: State
            let subpath: String
            let basedOn: Dependency?

            init(_ dependency: ManagedDependency) {
                self.packageRef = .init(dependency.packageRef)
                self.state = .init(underlying: dependency.state)
                self.subpath = dependency.subpath.pathString
                self.basedOn = dependency.basedOn.map{ .init($0) }
            }

            struct State: Codable {
                let underlying: ManagedDependency.State

                init(underlying: ManagedDependency.State) {
                    self.underlying = underlying
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let kind = try container.decode(String.self, forKey: .name)
                    switch kind {
                    case "local":
                        self.init(underlying: .local)
                    case "checkout":
                        let checkout = try container.decode(CheckoutInfo.self, forKey: .checkoutState)
                        try self.init(underlying: .checkout(.init(checkout)))
                    case "edited":
                        let path = try container.decode(AbsolutePath?.self, forKey: .path)
                        self.init(underlying: .edited(path))
                    default:
                        throw InternalError("unknown checkout state \(kind)")
                    }
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self.underlying {
                    case .local:
                        try container.encode("local", forKey: .name)
                    case .checkout(let state):
                        try container.encode("checkout", forKey: .name)
                        try container.encode(CheckoutInfo(state), forKey: .checkoutState)
                    case .edited(let path):
                        try container.encode("edited", forKey: .name)
                        try container.encode(path, forKey: .path)

                    }
                }

                enum CodingKeys: CodingKey {
                    case name
                    case path
                    case checkoutState
                }

                struct CheckoutInfo: Codable {
                    let revision: String
                    let branch: String?
                    let version: String?

                    init(_ state: CheckoutState) {
                        switch state {
                        case .version(let version, let revision):
                            self.version = version.description
                            self.branch = nil
                            self.revision = revision.identifier
                        case .branch(let branch, let revision):
                            self.version = nil
                            self.branch = branch
                            self.revision = revision.identifier
                        case .revision(let revision):
                            self.version = nil
                            self.branch = nil
                            self.revision = revision.identifier
                        }
                    }
                }
            }
        }

        struct Artifact: Codable {
            let packageRef: PackageReference
            let targetName: String
            let source: Source
            let path: String

            init(_ artifact: Workspace.ManagedArtifact) {
                self.packageRef = .init(artifact.packageRef)
                self.targetName = artifact.targetName
                self.source = .init(underlying: artifact.source)
                self.path = artifact.path.pathString
            }

            struct Source: Codable {
                let underlying: Workspace.ManagedArtifact.Source

                init(underlying: Workspace.ManagedArtifact.Source) {
                    self.underlying = underlying
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let kind = try container.decode(String.self, forKey: .type)
                    switch kind {
                    case "local":
                        self.init(underlying: .local)
                    case "remote":
                        let url = try container.decode(String.self, forKey: .url)
                        let checksum = try container.decode(String.self, forKey: .checksum)
                        self.init(underlying: .remote(url: url, checksum: checksum))
                    default:
                        throw InternalError("unknown checkout state \(kind)")
                    }
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self.underlying {
                    case .local:
                        try container.encode("local", forKey: .type)
                    case .remote(let url, let checksum):
                        try container.encode("remote", forKey: .type)
                        try container.encode(url, forKey: .url)
                        try container.encode(checksum, forKey: .checksum)
                    }
                }

                enum CodingKeys: CodingKey {
                    case type
                    case url
                    case checksum
                }
            }
        }

        struct PackageReference: Codable {
            let identity: String
            let kind: String
            let location: String
            let name: String

            init (_ reference: PackageModel.PackageReference) {
                self.identity = reference.identity.description
                self.kind = reference.kind.rawValue
                self.location = reference.location
                self.name = reference.name // FIXME: not needed?
            }
        }
    }
}

extension ManagedDependency {
    fileprivate convenience init(_ dependency: WorkspaceStateStorage.V4.Dependency) {
        self.init(
            packageRef: .init(dependency.packageRef),
            state: dependency.state.underlying,
            subpath: RelativePath(dependency.subpath),
            basedOn: dependency.basedOn.map { .init($0) }
        )
    }
}

extension Workspace.ManagedArtifact {
    fileprivate init(_ artifact: WorkspaceStateStorage.V4.Artifact) {
        self.init(
            packageRef: .init(artifact.packageRef),
            targetName: artifact.targetName,
            source: artifact.source.underlying,
            path: AbsolutePath(artifact.path)
        )
    }
}

extension PackageModel.PackageReference {
    fileprivate init(_ reference: WorkspaceStateStorage.V4.PackageReference) {
        self.init(
            identity: .plain(reference.identity),
            // FIXME: remote should always be the case, but perhaps should validate?
            kind: .init(rawValue: reference.kind) ?? .remote,
            location: reference.location,
            name: reference.name // FIXME: drop
        )
    }
}

extension CheckoutState {
    fileprivate init(_ state: WorkspaceStateStorage.V4.Dependency.State.CheckoutInfo) throws {
        let revision: Revision = .init(identifier: state.revision)
        if let branch = state.branch {
            self = .branch(name: branch, revision: revision)
        } else if let version = state.version {
            self = try .version(Version(versionString: version), revision: revision)
        } else {
            self = .revision(revision)
        }
    }
}
