/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */


import PackageGraph
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility

/// A downloaded artifact managed by the workspace.
public struct ManagedArtifact {
    /// The package reference.
    public let packageRef: PackageReference

    /// The name of the binary target the artifact corresponds to.
    public let targetName: String

    /// The source of the artifact (local or remote).
    public let source: Source

    /// The path of the artifact on disk
    public let path: AbsolutePath

    public init(
        packageRef: PackageReference,
        targetName: String,
        source: Source,
        path: AbsolutePath
    ) {
        self.packageRef = packageRef
        self.targetName = targetName
        self.source = source
        self.path = path
    }

    /// Create an artifact downloaded from a remote url.
    public static func remote(
        packageRef: PackageReference,
        targetName: String,
        url: String,
        checksum: String,
        path: AbsolutePath
    ) -> ManagedArtifact {
        return ManagedArtifact(
            packageRef: packageRef,
            targetName: targetName,
            source: .remote(url: url, checksum: checksum),
            path: path
        )
    }

    /// Create an artifact present locally on the filesystem.
    public static func local(
        packageRef: PackageReference,
        targetName: String,
        path: AbsolutePath
    ) -> ManagedArtifact {
        return ManagedArtifact(
            packageRef: packageRef,
            targetName: targetName,
            source: .local,
            path: path
        )
    }

    /// Represents the source of the artifact.
    public enum Source: Equatable {

        /// Represents a remote artifact, with the url it was downloaded from, its checksum, and its path relative to
        /// the workspace artifacts path.
        case remote(url: String, checksum: String)

        /// Represents a locally available artifact, with its path relative to its package.
        case local
    }
}

// MARK: - CustomStringConvertible

extension ManagedArtifact: CustomStringConvertible {
    public var description: String {
        return "<ManagedArtifact: \(self.packageRef.name).\(self.targetName) \(self.source) \(self.path)>"
    }
}

extension ManagedArtifact.Source: CustomStringConvertible {
    public var description: String {
        switch self {
        case .local:
            return "local"
        case .remote(let url, let checksum):
            return "remote(url: \(url), checksum: \(checksum))"
        }
    }
}

// MARK: -

/// A collection of managed artifacts which have been downloaded.
public final class ManagedArtifacts {

    /// A mapping from package url, to target name, to ManagedArtifact.
    internal var artifactMap: [String: [String: ManagedArtifact]]

    internal var artifacts: AnyCollection<ManagedArtifact> {
        AnyCollection(artifactMap.values.lazy.flatMap({ $0.values }))
    }

    init(artifactMap: [String: [String: ManagedArtifact]] = [:]) {
        self.artifactMap = artifactMap
    }

    public subscript(packageURL packageURL: String, targetName targetName: String) -> ManagedArtifact? {
        artifactMap[packageURL]?[targetName]
    }

    public subscript(packageName packageName: String, targetName targetName: String) -> ManagedArtifact? {
        artifacts.first(where: { $0.packageRef.name == packageName && $0.targetName == targetName })
    }

    public func add(_ artifact: ManagedArtifact) {
        artifactMap[artifact.packageRef.location, default: [:]][artifact.targetName] = artifact
    }

    public func remove(packageURL: String, targetName: String) {
        artifactMap[packageURL]?[targetName] = nil
    }
}

// MARK: - Collection

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

// MARK: - CustomStringConvertible

extension ManagedArtifacts: CustomStringConvertible {
    public var description: String {
        "<ManagedArtifacts: \(Array(artifacts))>"
    }
}

