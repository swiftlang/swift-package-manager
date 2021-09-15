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

extension Workspace {
    /// A downloaded artifact managed by the workspace.
    public struct ManagedArtifact {
        /// The package reference.
        public let packageRef: PackageReference

        /// The name of the binary target the artifact corresponds to.
        public let targetName: String

        /// The source of the artifact (local, localArchived or remote).
        public let source: Source

        /// The path of the artifact on disk
        public let path: AbsolutePath

        /// Indicates if the artifact is located at the workspace artifacts path.
        public var isAtWorkspaceArtifactsPath: Bool {
            switch self.source {
            case .local:
                return false
            case .remote, .localArchived:
                return true
            }
        }

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
        
        /// Create an artifact extracted from a local archive path.
        public static func localArchived(
            packageRef: PackageReference,
            targetName: String,
            path: AbsolutePath,
            archivePath: AbsolutePath
        ) -> ManagedArtifact {
            return ManagedArtifact(
                packageRef: packageRef,
                targetName: targetName,
                source: .localArchived(archivePath: archivePath),
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
            
            /// Represents a local archived artifact, with the archive path it was extracted from, with its path relative to
            /// the workspace artifacts path.
            case localArchived(archivePath: AbsolutePath)
        }
    }
}

extension Workspace.ManagedArtifact: CustomStringConvertible {
    public var description: String {
        return "<ManagedArtifact: \(self.packageRef.name).\(self.targetName) \(self.source) \(self.path)>"
    }
}

extension Workspace.ManagedArtifact.Source: CustomStringConvertible {
    public var description: String {
        switch self {
        case .local:
            return "local"
        case .localArchived(let archivePath):
            return "localArchived(archivePath: \(archivePath.pathString))"
        case .remote(let url, let checksum):
            return "remote(url: \(url), checksum: \(checksum))"
        }
    }
}

// MARK: - ManagedArtifacts

extension Workspace {
    /// A collection of managed artifacts which have been downloaded.
    public final class ManagedArtifacts {
        /// A mapping from package identity, to target name, to ManagedArtifact.
        private var artifactMap: [PackageIdentity: [String: ManagedArtifact]]

        internal var artifacts: AnyCollection<ManagedArtifact> {
            AnyCollection(self.artifactMap.values.lazy.flatMap{ $0.values })
        }

        init(_ artifacts: [ManagedArtifact] = []) {
            let artifactsByPackagePath = Dictionary(grouping: artifacts, by: { $0.packageRef.identity })
            self.artifactMap = artifactsByPackagePath.mapValues{ artifacts in
                Dictionary(uniqueKeysWithValues: artifacts.map{ ($0.targetName, $0) })
            }
        }

        public subscript(packageIdentity packageIdentity: PackageIdentity, targetName targetName: String) -> ManagedArtifact? {
            self.artifactMap[packageIdentity]?[targetName]
        }

        public func add(_ artifact: ManagedArtifact) {
            self.artifactMap[artifact.packageRef.identity, default: [:]][artifact.targetName] = artifact
        }

        public func remove(packageIdentity: PackageIdentity, targetName: String) {
            self.artifactMap[packageIdentity]?[targetName] = nil
        }
    }
}

extension Workspace.ManagedArtifacts: Collection {
    public var startIndex: AnyIndex {
        self.artifacts.startIndex
    }

    public var endIndex: AnyIndex {
        self.artifacts.endIndex
    }

    public subscript(index: AnyIndex) -> Workspace.ManagedArtifact {
        self.artifacts[index]
    }

    public func index(after index: AnyIndex) -> AnyIndex {
        self.artifacts.index(after: index)
    }
}

extension Workspace.ManagedArtifacts: CustomStringConvertible {
    public var description: String {
        "<ManagedArtifacts: \(Array(self.artifacts))>"
    }
}
