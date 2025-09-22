//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CoreCommands
import PackageFingerprint
import PackageRegistry
import PackageSigning
@_spi(PackageRefactor) import SwiftRefactor
import TSCBasic
import TSCUtility
import Workspace

import class PackageModel.Manifest
import struct PackageModel.PackageIdentity

/// A protocol defining interfaces for resolving package dependency requirements
/// based on versioning input (e.g., version, branch, or revision).
protocol DependencyRequirementResolving {
    func resolveSourceControl() throws -> SwiftRefactor.PackageDependency.SourceControl.Requirement
    func resolveRegistry() async throws -> SwiftRefactor.PackageDependency.Registry.Requirement?
}

/// A utility for resolving a single, well-formed package dependency requirement
/// from mutually exclusive versioning inputs, such as:
/// - `exact`: A specific version (e.g., 1.2.3)
/// - `branch`: A branch name (e.g., "main")
/// - `revision`: A commit hash or VCS revision
/// - `from` / `upToNextMinorFrom`: Lower bounds for version ranges
/// - `to`: An optional upper bound that refines a version range
///
/// This resolver ensures only one form of versioning input is specified and validates combinations like `to` with
/// `from`.

struct DependencyRequirementResolver: DependencyRequirementResolving {
    /// Package-id for registry
    let packageIdentity: String?
    /// SwiftCommandstate
    let swiftCommandState: SwiftCommandState
    /// An exact version to use.
    let exact: Version?

    /// A specific source control revision (e.g., a commit SHA).
    let revision: String?

    /// A branch name to track.
    let branch: String?

    /// The lower bound for a version range with an implicit upper bound to the next major version.
    let from: Version?

    /// The lower bound for a version range with an implicit upper bound to the next minor version.
    let upToNextMinorFrom: Version?

    /// An optional manual upper bound for the version range. Must be used with `from` or `upToNextMinorFrom`.
    let to: Version?

    /// Internal helper for resolving a source control (Git) requirement.
    ///
    /// - Returns: A valid `PackageDependency.SourceControl.Requirement`.
    /// - Throws: `StringError` if multiple or no input fields are set, or if `to` is used without `from` or
    /// `upToNextMinorFrom`.
    func resolveSourceControl() throws -> SwiftRefactor.PackageDependency.SourceControl.Requirement {
        var specifiedRequirements: [SwiftRefactor.PackageDependency.SourceControl.Requirement] = []

        if let exact {
            specifiedRequirements.append(.exact(exact.description))
        }

        if let branch {
            specifiedRequirements.append(.branch(branch))
        }

        if let revision {
            specifiedRequirements.append(.revision(revision))
        }

        if let from {
            specifiedRequirements.append(.rangeFrom(from.description))
        }

        if let upToNextMinorFrom {
            let range: Range<Version> = .upToNextMinor(from: upToNextMinorFrom)
            specifiedRequirements.append(
                .range(
                    lowerBound: range.lowerBound.description,
                    upperBound: range.upperBound.description
                )
            )
        }

        guard !specifiedRequirements.isEmpty else {
            throw DependencyRequirementError.noRequirementSpecified
        }

        guard specifiedRequirements.count == 1, let firstRequirement = specifiedRequirements.first else {
            throw DependencyRequirementError.multipleRequirementsSpecified
        }

        let requirement: PackageDependency.SourceControl.Requirement
        switch firstRequirement {
        case .range(let lowerBound, _), .rangeFrom(let lowerBound):
            requirement = if let to {
                .range(lowerBound: lowerBound, upperBound: to.description)
            } else {
                firstRequirement
            }
        default:
            requirement = firstRequirement

            if self.to != nil {
                throw DependencyRequirementError.invalidToParameterWithoutFrom
            }
        }

        return requirement
    }

    /// Internal helper for resolving a registry-based requirement.
    ///
    /// - Returns: A valid `PackageDependency.Registry.Requirement`.
    /// - Throws: `StringError` if more than one registry versioning input is provided or if `to` is used without a base
    /// range.
    func resolveRegistry() async throws -> SwiftRefactor.PackageDependency.Registry.Requirement? {
        if exact == nil, from == nil, upToNextMinorFrom == nil, self.to == nil {
            let config = try RegistryTemplateFetcher.getRegistriesConfig(self.swiftCommandState, global: true)
            let auth = try swiftCommandState.getRegistryAuthorizationProvider()

            guard let stringIdentity = self.packageIdentity else {
                throw DependencyRequirementError.noRequirementSpecified
            }
            let identity = PackageIdentity.plain(stringIdentity)
            let registryClient = RegistryClient(
                configuration: config.configuration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                skipSignatureValidation: false,
                signingEntityStorage: .none,
                signingEntityCheckingMode: .strict,
                authorizationProvider: auth,
                delegate: .none,
                checksumAlgorithm: SHA256()
            )

            let resolvedVersion = try await resolveVersion(for: identity, using: registryClient)
            return .exact(resolvedVersion.description)
        }

        var specifiedRequirements: [SwiftRefactor.PackageDependency.Registry.Requirement] = []

        if let exact {
            specifiedRequirements.append(.exact(exact.description))
        }

        if let from {
            specifiedRequirements.append(.rangeFrom(from.description))
        }

        if let upToNextMinorFrom {
            let range: Range<Version> = .upToNextMinor(from: upToNextMinorFrom)
            specifiedRequirements.append(
                .range(
                    lowerBound: range.lowerBound.description,
                    upperBound: range.upperBound.description
                )
            )
        }

        guard !specifiedRequirements.isEmpty else {
            throw DependencyRequirementError.noRequirementSpecified
        }

        guard specifiedRequirements.count == 1, let firstRequirement = specifiedRequirements.first else {
            throw DependencyRequirementError.multipleRequirementsSpecified
        }

        let requirement: SwiftRefactor.PackageDependency.Registry.Requirement
        switch firstRequirement {
        case .range(let lowerBound, _), .rangeFrom(let lowerBound):
            requirement = if let to {
                .range(lowerBound: lowerBound, upperBound: to.description)
            } else {
                firstRequirement
            }
        default:
            requirement = firstRequirement

            if self.to != nil {
                throw DependencyRequirementError.invalidToParameterWithoutFrom
            }
        }

        return requirement
    }

    /// Resolves the version to use for registry packages, fetching latest if none specified
    ///
    /// - Parameters:
    ///   - packageIdentity: The package identity to resolve version for
    ///   - registryClient: The registry client to use for fetching metadata
    /// - Returns: The resolved version to use
    /// - Throws: Error if version resolution fails
    func resolveVersion(
        for packageIdentity: PackageIdentity,
        using registryClient: RegistryClient
    ) async throws -> Version {
        let metadata = try await registryClient.getPackageMetadata(
            package: packageIdentity,
            observabilityScope: self.swiftCommandState.observabilityScope
        )

        guard let maxVersion = metadata.versions.max() else {
            throw DependencyRequirementError.failedToFetchLatestVersion(
                metadata: metadata,
                packageIdentity: packageIdentity
            )
        }

        return maxVersion
    }
}

/// Enum representing the type of dependency to resolve.
enum DependencyType {
    /// A source control dependency, such as a Git repository.
    case sourceControl
    /// A registry dependency, typically resolved from a package registry.
    case registry
}

enum DependencyRequirementError: Error, CustomStringConvertible, Equatable {
    case multipleRequirementsSpecified
    case noRequirementSpecified
    case invalidToParameterWithoutFrom
    case failedToFetchLatestVersion(metadata: RegistryClient.PackageMetadata, packageIdentity: PackageIdentity)

    var description: String {
        switch self {
        case .multipleRequirementsSpecified:
            "Specify exactly version requirement."
        case .noRequirementSpecified:
            "No exact or lower bound version requirement specified."
        case .invalidToParameterWithoutFrom:
            "--to requires --from or --up-to-next-minor-from"
        case .failedToFetchLatestVersion(let metadata, let packageIdentity):
            """
            Failed to fetch latest version of \(packageIdentity)
            Here is the metadata of the package you were trying to query:
            \(metadata)
            """
        }
    }

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.description == rhs.description
    }
}
