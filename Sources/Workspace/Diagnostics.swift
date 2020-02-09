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

public struct ManifestEmptyProductTargets: DiagnosticData {
    public let productName: String

    public var description: String {
        "manifest parse error: product '\(productName)' doesn't reference any targets\n"
    }
}

public struct ManifestProductTargetNotFound: DiagnosticData {
    public let productName: String
    public let targetName: String

    public var description: String {
        "manifest parse error: target '\(targetName)' referenced in product '\(productName)' could not be found\n"
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

public struct ManifestUnknownTargetDependencyDiagnostic: DiagnosticData {
    public let dependency: String
    public let targetName: String

    public var description: String {
        "unknown dependency '\(dependency)' in target '\(targetName)'"
    }
}

public struct ManifestUnknownTargetPackageDependencyDiagnostic: DiagnosticData {
    public let packageName: String
    public let targetName: String

    public var description: String {
        "unknown package '\(packageName)' in dependencies of target '\(targetName)'"
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

public struct ManifestDuplicateTargetNamesDiagnostic: DiagnosticData {
    public let duplicates: [String]

    public var description: String {
        "manifest parse error: duplicate target names: \(duplicates.joined(separator: ", "))\n"
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
            return ManifestEmptyProductTargets(productName: productName)
        case .productTargetNotFound(let productName, let targetName):
            return ManifestProductTargetNotFound(productName: productName, targetName: targetName)
        case .duplicateDependencyURLs(let duplicates):
            return ManifestDuplicateDependencyURLsDiagnostic(duplicates: duplicates)
        case .duplicateTargetNames(let targetNames):
            return ManifestDuplicateTargetNamesDiagnostic(duplicates: targetNames)
        case .unknownTargetDependency(let dependency, let targetName):
            return ManifestUnknownTargetDependencyDiagnostic(dependency: dependency, targetName: targetName)
        case .unknownTargetPackageDependency(let packageName, let targetName):
            return ManifestUnknownTargetPackageDependencyDiagnostic(packageName: packageName, targetName: targetName)
        case .duplicateDependencyNames(let duplicates):
            return ManifestDuplicateDependencyNamesDiagnostic(duplicates: duplicates)
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
}
