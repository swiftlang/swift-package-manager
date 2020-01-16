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

public struct ManifestDuplicateDependencyURLsDiagnostic: DiagnosticData {
    public let duplicates: [[PackageDependencyDescription]]

    public var description: String {
        let stream = BufferedOutputByteStream()

        stream <<< "manifest parse error(s): duplicate dependency URLs\n"
        let indent = Format.asRepeating(string: " ", count: 4)

        for duplicateGroup in duplicates {
            for duplicate in duplicateGroup {
                stream <<< indent <<< duplicate.url <<< " @ " <<< "\(duplicate.requirement)" <<< "\n"
            }
            stream <<< "\n"
        }

        return stream.bytes.description
    }
}

public struct ManifestDuplicateDependencyNamesDiagnostic: DiagnosticData {
    public let duplicates: [[PackageDependencyDescription]]

    public var description: String {
        let stream = BufferedOutputByteStream()

        stream <<< "manifest parse error(s): duplicate dependency names\n"
        let indent = Format.asRepeating(string: " ", count: 4)

        for duplicateGroup in duplicates {
            for duplicate in duplicateGroup {
                stream <<< indent <<< duplicate.url <<< " @ " <<< "\(duplicate.requirement)" <<< "\n"
            }
            stream <<< "\n"
        }

        stream <<< "consider differentiating them using the 'name' argument.\n"
        return stream.bytes.description
    }
}

extension ManifestParseError: DiagnosticDataConvertible {
    public var diagnosticData: DiagnosticData {
        switch self {
        case .invalidManifestFormat(let error, let diagnisticFile):
            return ManifestParseDiagnostic([error], diagnosticFile: diagnisticFile)
        case .runtimeManifestErrors(let errors):
            return ManifestParseDiagnostic(errors, diagnosticFile: nil)
        case .emptyProductTargets(let productName):
            return Diagnostic.Message.emptyProductTargets(productName: productName).data
        case .productTargetNotFound(let productName, let targetName):
            return Diagnostic.Message.productTargetNotFound(productName: productName, targetName: targetName).data
        case .invalidBinaryProductType(let productName):
            return Diagnostic.Message.invalidBinaryProductType(productName: productName).data
        case .duplicateDependencyURLs(let duplicates):
            return ManifestDuplicateDependencyURLsDiagnostic(duplicates: duplicates)
        case .duplicateTargetNames(let targetNames):
            return Diagnostic.Message.duplicateTargetNames(duplicates: targetNames).data
        case .unknownTargetDependencyPackage(let targetName, let packageName):
            return Diagnostic.Message.unknownTargetDependencyPackage(targetName: targetName, packageName: packageName).data
        case .duplicateDependencyNames(let duplicates):
            return ManifestDuplicateDependencyNamesDiagnostic(duplicates: duplicates)
        case .invalidBinaryLocation(let targetName):
            return Diagnostic.Message.invalidBinaryLocation(targetName: targetName).data
        case .invalidBinaryURLScheme(let targetName, let validSchemes):
            return Diagnostic.Message.invalidBinaryURLScheme(targetName: targetName, validSchemes: validSchemes).data
        case .invalidBinaryLocationExtension(let targetName, let validExtensions):
            return Diagnostic.Message.invalidBinaryLocationExtension(targetName: targetName, validExtensions: validExtensions).data
        }
    }
}

public enum ResolverDiagnostics {

    public struct Unsatisfiable: DiagnosticData {
        static func toString(_ constraint: RepositoryPackageConstraint) -> String {
            let stream = BufferedOutputByteStream()
            stream <<< constraint.identifier.path <<< " @ "

            switch constraint.requirement {
            case .versionSet(let set):
                stream <<< set.description
            case .revision(let revision):
                stream <<< revision
            case .unversioned:
                stream <<< "unversioned"
            }

            return stream.bytes.description
        }

        /// The conflicting dependencies.
        public let dependencies: [RepositoryPackageConstraint]

        /// The conflicting pins.
        public let pins: [RepositoryPackageConstraint]

        public init( dependencies: [RepositoryPackageConstraint], pins: [RepositoryPackageConstraint]) {
            self.dependencies = dependencies
            self.pins = pins
        }

        public var description: String {
            var diag = "the package dependency graph could not be resolved"

            // If we don't have any additional data, return empty string.
            if self.dependencies.isEmpty && self.pins.isEmpty {
                return diag
            }

            diag += "; possibly because of these requirements:"
            let indent = "    "

            if !self.dependencies.isEmpty {
                diag += self.dependencies.map({ indent + Unsatisfiable.toString($0) }).joined(separator: "\n")
            }

            return diag
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

    static func artifactInvalidChecksum(targetName: String) -> Diagnostic.Message {
        .error("downloaded artifact of binary target '\(targetName)' has an invalid checksum")
    }

    static func artifactFailedDownload(targetName: String, reason: String) -> Diagnostic.Message {
        .error("artifact of binary target '\(targetName)' failed download: \(reason)")
    }

    static func artifactFailedExtraction(targetName: String, reason: String) -> Diagnostic.Message {
        .error("artifact of binary target '\(targetName)' failed extraction: \(reason)")
    }

    static func productTargetNotFound(productName: String, targetName: String) -> Diagnostic.Message {
        .error("manifest parse error: target '\(targetName)' referenced in product '\(productName)' could not be found")
    }

    static func emptyProductTargets(productName: String) -> Diagnostic.Message {
        .error("manifest parse error: product '\(productName)' doesn't reference any targets")
    }

    static func invalidBinaryProductType(productName: String) -> Diagnostic.Message {
        .error("manifest parse error: invalid type for binary product '\(productName)'; a binary product can only be a library with no defined type")
    }

    static func duplicateTargetNames(duplicates: [String]) -> Diagnostic.Message {
        .error("manifest parse error: duplicate target names: \(duplicates.joined(separator: ", "))")
    }

    static func unknownTargetDependencyPackage(targetName: String, packageName: String) -> Diagnostic.Message {
        .error("manifest parse error: target '\(targetName)' depends on an unknown package '\(packageName)'")
    }

    static func invalidBinaryLocation(targetName: String) -> Diagnostic.Message {
        .error("manifest parse error: invalid location of binary target '\(targetName)'")
    }

    static func invalidBinaryURLScheme(targetName: String, validSchemes: [String]) -> Diagnostic.Message {
        .error("manifest parse error: invalid URL scheme for binary target '\(targetName)' (valid schemes are \(validSchemes.joined(separator: ", "))")
    }

    static func invalidBinaryLocationExtension(targetName: String, validExtensions: [String]) -> Diagnostic.Message {
        .error("manifest parse error: unsupported extension of binary target '\(targetName)' (valid extensions are \(validExtensions.joined(separator: ", "))")
    }
}
