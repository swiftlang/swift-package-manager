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

/// A utility for resolving a single, well-formed source control dependency requirement
/// based on mutually exclusive versioning inputs such as `exact`, `branch`, `revision`,
/// or version ranges (`from`, `upToNextMinorFrom`, `to`).
///
/// This is typically used to translate user-specified version inputs (e.g., from the command line)
/// into a concrete `PackageDependency.SourceControl.Requirement` that SwiftPM can understand.
///
/// Only one of the following fields should be non-nil:
/// - `exact`: A specific version (e.g., 1.2.3).
/// - `revision`: A specific VCS revision (e.g., commit hash).
/// - `branch`: A named branch (e.g., "main").
/// - `from`: Lower bound of a version range with an upper bound inferred as the next major version.
/// - `upToNextMinorFrom`: Lower bound of a version range with an upper bound inferred as the next minor version.
///
/// Optionally, a `to` value can be specified to manually cap the upper bound of a version range,
/// but it must be combined with `from` or `upToNextMinorFrom`.

struct DependencyRequirementResolver {
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

    /// Resolves the provided requirement fields into a concrete `PackageDependency.SourceControl.Requirement`.
    ///
    /// - Returns: A valid, single requirement representing a source control constraint.
    /// - Throws: A `StringError` if:
    ///   - More than one requirement type is provided.
    ///   - None of the requirement fields are set.
    ///   - A `to` value is provided without a corresponding `from` or `upToNextMinorFrom`.

    func resolve() throws -> PackageDependency.SourceControl.Requirement {
        var all: [PackageDependency.SourceControl.Requirement] = []

        if let v = exact { all.append(.exact(v)) }
        if let b = branch { all.append(.branch(b)) }
        if let r = revision { all.append(.revision(r)) }
        if let f = from { all.append(.range(.upToNextMajor(from: f))) }
        if let u = upToNextMinorFrom { all.append(.range(.upToNextMinor(from: u))) }

        guard all.count == 1, let requirement = all.first else {
            throw StringError("Specify exactly one version requirement.")
        }

        if case .range(let range) = requirement, let upper = to {
            return .range(range.lowerBound ..< upper)
        } else if self.to != nil {
            throw StringError("--to requires --from or --up-to-next-minor-from")
        }

        return requirement
    }
}
