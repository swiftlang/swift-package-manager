/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCUtility
import PackageModel
import PackageLoading
import PackageGraph
import Foundation

public struct ManifestParseDiagnostic: DiagnosticData {
    public let errors: [String]
    public let diagnosticFile: AbsolutePath?

    public init(_ errors: [String], diagnosticFile: AbsolutePath?) {
        self.errors = errors
        self.diagnosticFile = diagnosticFile
    }

    public var description: String {
        "manifest parse error(s):\n" + errors.joined(separator: "\n")
    }
}

extension ManifestParseError: DiagnosticDataConvertible {
    public var diagnosticData: DiagnosticData {
        switch self {
        case .invalidManifestFormat(let error, let diagnisticFile):
            return ManifestParseDiagnostic([error], diagnosticFile: diagnisticFile)
        case .runtimeManifestErrors(let errors):
            return ManifestParseDiagnostic(errors, diagnosticFile: nil)
        }
    }
}

public struct InvalidToolchainDiagnostic: DiagnosticData, Error {
    public let error: String

    public init(_ error: String) {
        self.error = error
    }

    public var description: String {
        "toolchain is invalid: \(error)"
    }
}

public enum WorkspaceDiagnostics {

    // MARK: - Errors

    /// The diagnostic triggered when an operation fails because its completion
    /// would lose the uncommited changes in a repository.
    public struct UncommitedChanges: DiagnosticData, Swift.Error {
        /// The local path to the repository.
        public let repositoryPath: AbsolutePath

        public var description: String {
            return "repository '\(repositoryPath)' has uncommited changes"
        }
    }

    /// The diagnostic triggered when an operation fails because its completion
    /// would loose the unpushed changes in a repository.
    public struct UnpushedChanges: DiagnosticData, Swift.Error {
        /// The local path to the repository.
        public let repositoryPath: AbsolutePath

        public var description: String {
            return "repository '\(repositoryPath)' has unpushed changes"
        }
    }

    /// The diagnostic triggered when the unedit operation fails because the dependency
    /// is not in edit mode.
    public struct DependencyNotInEditMode: DiagnosticData, Swift.Error {
        /// The name of the dependency being unedited.
        public let dependencyName: String

        public var description: String {
            return "dependency '\(dependencyName)' not in edit mode"
        }
    }

    /// The diagnostic triggered when the edit operation fails because the branch
    /// to be created already exists.
    public struct BranchAlreadyExists: DiagnosticData, Swift.Error {
        /// The branch to create.
        public let branch: String

        public var description: String {
            return "branch '\(branch)' already exists"
        }
    }

    /// The diagnostic triggered when the edit operation fails because the specified
    /// revision does not exist.
    public struct RevisionDoesNotExist: DiagnosticData, Swift.Error {
        /// The revision requested.
        public let revision: String

        public var description: String {
            return "revision '\(revision)' does not exist"
        }
    }
}

extension Diagnostic.Message {
    static func dependencyNotFound(packageName: String) -> Diagnostic.Message {
        .warning("dependency '\(packageName)' was not found")
    }

    static func editBranchNotCheckedOut(packageName: String, branchName: String) -> Diagnostic.Message {
        .warning("dependency '\(packageName)' already exists at the edit destination; not checking-out branch '\(branchName)'")
    }

    static func editRevisionNotUsed(packageName: String, revisionIdentifier: String) -> Diagnostic.Message {
        .warning("dependency '\(packageName)' already exists at the edit destination; not using revision '\(revisionIdentifier)'")
    }

    static func editedDependencyMissing(packageName: String) -> Diagnostic.Message {
        .warning("dependency '\(packageName)' was being edited but is missing; falling back to original checkout")
    }

    static func checkedOutDependencyMissing(packageName: String) -> Diagnostic.Message {
        .warning("dependency '\(packageName)' is missing; cloning again")
    }

    static func artifactChecksumChanged(targetName: String) -> Diagnostic.Message {
        .error("artifact of binary target '\(targetName)' has changed checksum; this is a potential security risk so the new artifact won't be downloaded")
    }

    static func artifactInvalidChecksum(targetName: String, expectedChecksum: String, actualChecksum: String) -> Diagnostic.Message {
        .error("checksum of downloaded artifact of binary target '\(targetName)' (\(actualChecksum)) does not match checksum specified by the manifest (\(expectedChecksum))")
    }

    static func artifactFailedDownload(targetName: String, reason: String) -> Diagnostic.Message {
        .error("artifact of binary target '\(targetName)' failed download: \(reason)")
    }

    static func artifactFailedExtraction(targetName: String, reason: String) -> Diagnostic.Message {
        .error("artifact of binary target '\(targetName)' failed extraction: \(reason)")
    }

    static func artifactNotFound(targetName: String, artifactName: String) -> Diagnostic.Message {
        .error("downloaded archive of binary target '\(targetName)' does not contain expected binary artifact '\(artifactName)'")
    }
}


extension FileSystemError: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .invalidAccess:
            return "invalid access"
        case .ioError:
            return "encountered I/O error"
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
        }
    }
}
