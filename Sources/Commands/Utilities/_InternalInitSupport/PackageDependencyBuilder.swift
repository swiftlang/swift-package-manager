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

import Basics
import Foundation
import TSCBasic
import TSCUtility
import Workspace
@_spi(PackageRefactor) import SwiftRefactor


/// A protocol for building `MappablePackageDependency.Kind` instances from provided dependency information.
///
/// Conforming types are responsible for converting high-level dependency configuration
/// (such as template source type and associated metadata) into a concrete dependency
/// that SwiftPM can work with.
protocol PackageDependencyBuilder {
    /// Constructs a `MappablePackageDependency.Kind` based on the provided requirements and template path.
    ///
    /// - Parameters:
    ///   - sourceControlRequirement: The source control requirement (e.g., Git-based), if applicable.
    ///   - registryRequirement: The registry requirement, if applicable.
    ///   - resolvedTemplatePath: The resolved absolute path to a local package template, if applicable.
    ///
    /// - Returns: A concrete `MappablePackageDependency.Kind` value.
    ///
    /// - Throws: A `StringError` if required inputs (e.g., Git URL, Package ID) are missing or invalid for the selected
    /// source type.
    func makePackageDependency() throws -> PackageDependency
}

/// Default implementation of `PackageDependencyBuilder` that builds a package dependency
/// from a given template source and metadata.
///
/// This struct is typically used when initializing new packages from templates via SwiftPM.
struct DefaultPackageDependencyBuilder: PackageDependencyBuilder {
    /// The source type of the package template (e.g., local file system, Git repository, or registry).
    let templateSource: InitTemplatePackage.TemplateSource

    /// The name to assign to the resulting package dependency.
    let packageName: String

    /// The URL of the Git repository, if the template source is Git-based.
    let templateURL: String?

    /// The registry package identifier, if the template source is registry-based.
    let templatePackageID: String?


    let sourceControlRequirement: PackageDependency.SourceControl.Requirement?
    let registryRequirement: PackageDependency.Registry.Requirement?
    let resolvedTemplatePath: Basics.AbsolutePath


    /// Constructs a package dependency kind based on the selected template source.
    ///
    /// - Parameters:
    ///   - sourceControlRequirement: The requirement for Git-based dependencies.
    ///   - registryRequirement: The requirement for registry-based dependencies.
    ///   - resolvedTemplatePath: The local file path for filesystem-based dependencies.
    ///
    /// - Returns: A `MappablePackageDependency.Kind` representing the dependency.
    ///
    /// - Throws: A `StringError` if necessary information is missing or mismatched for the selected template source.
    func makePackageDependency() throws -> PackageDependency {
        switch self.templateSource {
        case .local:
            return .fileSystem(.init(path: resolvedTemplatePath.asURL.path))
        case .git:
            guard let url = templateURL else {
                throw PackageDependencyBuilderError.missingGitURLOrPath
            }
            guard let requirement = sourceControlRequirement else {
                throw PackageDependencyBuilderError.missingGitRequirement
            }
            return .sourceControl(.init(location: url, requirement: requirement))

        case .registry:
            guard let id = templatePackageID else {
                throw PackageDependencyBuilderError.missingRegistryIdentity
            }
            guard let requirement = registryRequirement else {
                throw PackageDependencyBuilderError.missingRegistryRequirement
            }
            return .registry(.init(identity: id, requirement: requirement))
        }
    }


    /// Errors thrown by `TemplatePathResolver` during initialization.
    enum PackageDependencyBuilderError: LocalizedError, Equatable {
        case missingGitURLOrPath
        case missingGitRequirement
        case missingRegistryIdentity
        case missingRegistryRequirement

        var errorDescription: String? {
            switch self {
            case .missingGitURLOrPath:
                return "Missing Git URL or path for template from git."
            case .missingGitRequirement:
                return "Missing version requirement for template from git."
            case .missingRegistryIdentity:
                return "Missing registry package identity for template from registry."
            case .missingRegistryRequirement:
                return "Missing version requirement for template from registry ."
            }
        }
    }

}
