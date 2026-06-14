//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageGraph
import PackageLoading
import PackageModel

import struct TSCBasic.FileSystemError

public struct ManifestParseDiagnostic: CustomStringConvertible {
    public let errors: [String]
    public let diagnosticFile: AbsolutePath?

    public init(_ errors: [String], diagnosticFile: AbsolutePath?) {
        self.errors = errors
        self.diagnosticFile = diagnosticFile
    }

    public var description: String {
        "manifest parse error(s):\n" + self.errors.joined(separator: "\n")
    }
}

public enum WorkspaceDiagnostics {
    // MARK: - Errors

    /// The diagnostic triggered when an operation fails because its completion
    /// would lose the uncommitted changes in a repository.
    public struct UncommittedChanges: Error, CustomStringConvertible {
        /// The local path to the repository.
        public let repositoryPath: AbsolutePath

        public var description: String {
            "repository '\(self.repositoryPath)' has uncommitted changes"
        }
    }

    /// The diagnostic triggered when an operation fails because its completion
    /// would lose the unpushed changes in a repository.
    public struct UnpushedChanges: Error, CustomStringConvertible {
        /// The local path to the repository.
        public let repositoryPath: AbsolutePath

        public var description: String {
            "repository '\(self.repositoryPath)' has unpushed changes"
        }
    }

    /// The diagnostic triggered when the unedit operation fails because the dependency
    /// is not in edit mode.
    public struct DependencyNotInEditMode: Error, CustomStringConvertible {
        /// The name of the dependency being unedited.
        public let dependencyName: String

        public var description: String {
            "dependency '\(self.dependencyName)' not in edit mode"
        }
    }

    /// The diagnostic triggered when the edit operation fails because the branch
    /// to be created already exists.
    public struct BranchAlreadyExists: Error, CustomStringConvertible {
        /// The branch to create.
        public let branch: String

        public var description: String {
            "branch '\(self.branch)' already exists"
        }
    }

    /// The diagnostic triggered when the edit operation fails because the specified
    /// revision does not exist.
    public struct RevisionDoesNotExist: Error, CustomStringConvertible {
        /// The revision requested.
        public let revision: String

        public var description: String {
            "revision '\(self.revision)' does not exist"
        }
    }
}

extension Basics.Diagnostic {
    static func dependencyNotFound(packageName: String) -> Self {
        .warning("dependency '\(packageName)' was not found")
    }

    static func editBranchNotCheckedOut(packageName: String, branchName: String) -> Self {
        .warning(
            "dependency '\(packageName)' already exists at the edit destination; not checking-out branch '\(branchName)'"
        )
    }

    static func editRevisionNotUsed(packageName: String, revisionIdentifier: String) -> Self {
        .warning(
            "dependency '\(packageName)' already exists at the edit destination; not using revision '\(revisionIdentifier)'"
        )
    }

    static func editedDependencyMissing(packageName: String) -> Self {
        .warning("dependency '\(packageName)' was being edited but is missing; falling back to original checkout")
    }

    static func checkedOutDependencyMissing(packageName: String) -> Self {
        .warning("dependency '\(packageName)' is missing; cloning again")
    }

    static func registryDependencyMissing(packageName: String) -> Self {
        .warning("dependency '\(packageName)' is missing; downloading again")
    }

    static func customDependencyMissing(packageName: String) -> Self {
        .warning("dependency '\(packageName)' is missing; retrieving again")
    }
}

struct BinaryArtifactsManagerError: Error, CustomStringConvertible {
    let description: String

    private init(description: String) {
        self.description = description
    }

    static func artifactInvalidArchive(artifact: Workspace.BinaryArtifactsManager.RemoteArtifact) -> Self {
        .init(
            description: "invalid archive returned from '\(artifact.url.absoluteString)' which is required by binary target '\(artifact.targetName)'"
        )
    }

    static func artifactChecksumChanged(artifact: Workspace.BinaryArtifactsManager.RemoteArtifact) -> Self {
        .init(
            description: "artifact of binary target '\(artifact.targetName)' has changed checksum; this is a potential security risk so the new artifact won't be downloaded"
        )
    }

    static func artifactInvalidChecksum(artifact: Workspace.BinaryArtifactsManager.RemoteArtifact, actualChecksum: String?) -> Self {
        .init(
            description: "checksum of downloaded artifact of binary target '\(artifact.targetName)' (\(actualChecksum ?? "none")) does not match checksum specified by the manifest (\(artifact.checksum))"
        )
    }

    static func artifactFailedDownload(target: TargetDescription, artifactURL: URL, reason: String) -> Self {
        .init(
            description: "failed downloading '\(artifactURL.absoluteString)' which is required by binary target '\(target.name)': \(reason)"
        )
    }

    static func artifactFailedDownload(artifact: Workspace.BinaryArtifactsManager.RemoteArtifact, reason: String) -> Self {
        .init(
            description: "failed downloading '\(artifact.url.absoluteString)' which is required by binary target '\(artifact.targetName)': \(reason)"
        )
    }

    static func artifactFailedValidation(artifact: Workspace.BinaryArtifactsManager.RemoteArtifact, reason: String) -> Self {
        .init(
            description: "failed validating archive from '\(artifact.url.absoluteString)' which is required by binary target '\(artifact.targetName)': \(reason)"
        )
    }

    static func remoteArtifactFailedExtraction(artifact: Workspace.BinaryArtifactsManager.RemoteArtifact, reason: String) -> Self {
        .init(
            description: "failed extracting '\(artifact.url.absoluteString)' which is required by binary target '\(artifact.targetName)': \(reason)"
        )
    }

    static func localArtifactFailedExtraction(artifact: Workspace.ManagedArtifact, reason: String) -> Self {
        .init(description: "failed extracting '\(artifact.path)' which is required by binary target '\(artifact.targetName)': \(reason)")
    }

    static func remoteArtifactNotFound(artifact: Workspace.BinaryArtifactsManager.RemoteArtifact) -> Self {
        .init(
            description: "downloaded archive of binary target '\(artifact.targetName)' from '\(artifact.url.absoluteString)' does not contain a binary artifact."
        )
    }

    static func localArchivedArtifactNotFound(artifact: Workspace.ManagedArtifact) -> Self {
        .init(description: "local archive of binary target '\(artifact.targetName)' at '\(artifact.path)' does not contain a binary artifact.")
    }

    static func localArtifactNotFound(target: TargetDescription, artifactPath: AbsolutePath) -> Self {
        .init(description: "local binary target '\(target.name)' at '\(artifactPath)' does not contain a binary artifact.")
    }

    static func localArtifactNotFound(artifact: Workspace.ManagedArtifact) -> Self {
        .init(description: "local binary target '\(artifact.targetName)' at '\(artifact.path)' does not contain a binary artifact.")
    }

    static func artifactContainsEscapingSymlink(
        targetName: String,
        symlinkPath: AbsolutePath,
        destination: String
    ) -> Self {
        .init(
            description: "archive of binary target '\(targetName)' contains a symlink at '\(symlinkPath.basename)' that points to '\(destination)' outside the archive directory"
        )
    }

    static func exhaustedAttempts(missing: [PackageReference]) -> Self {
        let missing = missing.sorted(by: { $0.identity < $1.identity }).map {
            switch $0.kind {
            case .registry(let identity):
                return "'\(identity.description)'"
            case .remoteSourceControl(let url):
                return "'\($0.identity)' from \(url)"
            case .localSourceControl(let path), .fileSystem(let path), .root(let path):
                return "'\($0.identity)' at \(path)"
            }
        }
        return .init(
            description: "exhausted attempts to resolve the dependencies graph, with the following dependencies unresolved:\n* \(missing.joined(separator: "\n* "))"
        )
    }
}

extension FileSystemError {
    public var description: String {
        guard let path else {
            switch self.kind {
            case .invalidAccess:
                return "invalid access"
            case .ioError(let code):
                return "encountered I/O error (code: \(code))"
            case .isDirectory:
                return "is a directory"
            case .noEntry:
                return "doesn't exist in file system"
            case .notDirectory:
                return "is not a directory"
            case .unsupported:
                return "unsupported operation"
            case .unknownOSError:
                return "unknown system error"
            case .alreadyExistsAtDestination:
                return "already exists in file system"
            case .couldNotChangeDirectory:
                return "could not change directory"
            case .mismatchedByteCount(expected: let expected, actual: let actual):
                return "mismatched byte count, expected \(expected), got \(actual)"
            }
        }

        switch self.kind {
        case .invalidAccess:
            return "invalid access to \(path)"
        case .ioError(let code):
            return "encountered an I/O error (code: \(code)) while reading \(path)"
        case .isDirectory:
            return "\(path) is a directory"
        case .noEntry:
            return "\(path) doesn't exist in file system"
        case .notDirectory:
            return "\(path) is not a directory"
        case .unsupported:
            return "unsupported operation on \(path)"
        case .unknownOSError:
            return "unknown system error while operating on \(path)"
        case .alreadyExistsAtDestination:
            return "\(path) already exists in file system"
        case .couldNotChangeDirectory:
            return "could not change directory to \(path)"
        case .mismatchedByteCount(expected: let expected, actual: let actual):
            return "mismatched byte count, expected \(expected), got \(actual)"
        }
    }
}

extension FileSystemError: @retroactive CustomStringConvertible {}
