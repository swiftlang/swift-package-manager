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

import PackageModel
import TSCBasic
import TSCUtility

/// A protocol defining interfaces for resolving package dependency requirements
/// based on versioning input (e.g., version, branch, or revision).
protocol DependencyRequirementResolving {
    func resolveSourceControl() throws -> PackageDependency.SourceControl.Requirement
    func resolveRegistry() throws -> PackageDependency.Registry.Requirement
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
    func resolveSourceControl() throws -> PackageDependency.SourceControl.Requirement {
        var requirements: [PackageDependency.SourceControl.Requirement] = []
        if let v = exact { requirements.append(.exact(v)) }
        if let b = branch { requirements.append(.branch(b)) }
        if let r = revision { requirements.append(.revision(r)) }
        if let f = from { requirements.append(.range(.upToNextMajor(from: f))) }
        if let u = upToNextMinorFrom { requirements.append(.range(.upToNextMinor(from: u))) }

        guard requirements.count == 1, let requirement = requirements.first else {
            throw StringError("Specify exactly one source control version requirement.")
        }

        if case .range(let range) = requirement, let upper = to {
            return .range(range.lowerBound ..< upper)
        } else if self.to != nil {
            throw StringError("--to requires --from or --up-to-next-minor-from")
        }

        return requirement
    }

    /// Internal helper for resolving a registry-based requirement.
    ///
    /// - Returns: A valid `PackageDependency.Registry.Requirement`.
    /// - Throws: `StringError` if more than one registry versioning input is provided or if `to` is used without a base
    /// range.
    func resolveRegistry() throws -> PackageDependency.Registry.Requirement {
        var requirements: [PackageDependency.Registry.Requirement] = []

        if let v = exact { requirements.append(.exact(v)) }
        if let f = from { requirements.append(.range(.upToNextMajor(from: f))) }
        if let u = upToNextMinorFrom { requirements.append(.range(.upToNextMinor(from: u))) }

        guard requirements.count == 1, let requirement = requirements.first else {
            throw StringError("Specify exactly one source control version requirement.")
        }

        if case .range(let range) = requirement, let upper = to {
            return .range(range.lowerBound ..< upper)
        } else if self.to != nil {
            throw StringError("--to requires --from or --up-to-next-minor-from")
        }

        return requirement
    }
}

/// Enum representing the type of dependency to resolve.
enum DependencyType {
    /// A source control dependency, such as a Git repository.
    case sourceControl
    /// A registry dependency, typically resolved from a package registry.
    case registry
}
