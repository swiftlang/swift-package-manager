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
import PackageModel
import SourceControl
import TSCBasic
import TSCUtility
import Workspace

/// A utility responsible for resolving the path to a package template,
/// based on the provided template type and associated configuration.
///
/// Supported template types include:
/// - `.local`: A local file system path to a template directory.
/// - `.git`: A remote Git repository containing the template.
/// - `.registry`: (Currently unsupported)
///
/// Used during package initialization (e.g., via `swift package init --template`).

struct TemplatePathResolver {
    /// The type of template to resolve (e.g., local, git, registry).
    let templateType: InitTemplatePackage.TemplateSource?

    /// The local path to a template directory, used for `.local` templates.
    let templateDirectory: Basics.AbsolutePath?

    /// The URL of the Git repository containing the template, used for `.git` templates.
    let templateURL: String?

    /// The versioning requirement for the Git repository (e.g., exact version, branch, revision, or version range).
    let requirement: PackageDependency.SourceControl.Requirement?

    /// Resolves the template path by downloading or validating it based on the template type.
    ///
    /// - Returns: The resolved path to the template directory.
    /// - Throws:
    /// - `StringError` if required values (e.g., path, URL, requirement) are missing,
    /// or if the template type is unsupported or unspecified.
    func resolve() async throws -> Basics.AbsolutePath {
        switch self.templateType {
        case .local:
            guard let path = templateDirectory else {
                throw StringError("Template path must be specified for local templates.")
            }
            return path

        case .git:
            guard let url = templateURL else {
                throw StringError("Missing Git URL for git template.")
            }

            guard let gitRequirement = requirement else {
                throw StringError("Missing version requirement for git template.")
            }

            return try await GitTemplateFetcher(destination: url, requirement: gitRequirement).fetch()

        case .registry:
            throw StringError("Registry templates not supported yet.")

        case .none:
            throw StringError("Missing --template-type.")
        }
    }

    /// A helper that fetches a Git-based template repository and checks out the specified version or revision.
    struct GitTemplateFetcher {
        /// The Git URL of the remote repository.
        let destination: String

        /// The source control requirement used to determine which version/branch/revision to check out.
        let requirement: PackageDependency.SourceControl.Requirement

        /// Fetches the repository and returns the path to the checked-out working copy.
        ///
        /// - Returns: A path to the directory containing the fetched template.
        /// - Throws: Any error encountered during repository fetch, checkout, or validation.
        func fetch() async throws -> Basics.AbsolutePath {
            let fetchStandalonePackageByURL = { () async throws -> Basics.AbsolutePath in
                try withTemporaryDirectory(removeTreeOnDeinit: false) { (tempDir: Basics.AbsolutePath) in

                    let url = SourceControlURL(destination)
                    let repositorySpecifier = RepositorySpecifier(url: url)
                    let repositoryProvider = GitRepositoryProvider()

                    let bareCopyPath = tempDir.appending(component: "bare-copy")

                    let workingCopyPath = tempDir.appending(component: "working-copy")

                    try self.fetchBareRepository(
                        provider: repositoryProvider,
                        specifier: repositorySpecifier,
                        to: bareCopyPath
                    )
                    try self.validateDirectory(provider: repositoryProvider, at: bareCopyPath)

                    try FileManager.default.createDirectory(
                        atPath: workingCopyPath.pathString,
                        withIntermediateDirectories: true
                    )

                    let repository = try repositoryProvider.createWorkingCopyFromBare(
                        repository: repositorySpecifier,
                        sourcePath: bareCopyPath,
                        at: workingCopyPath,
                        editable: true
                    )

                    try FileManager.default.removeItem(at: bareCopyPath.asURL)

                    try self.checkout(repository: repository)

                    return workingCopyPath
                }
            }

            return try await fetchStandalonePackageByURL()
        }

        /// Fetches a bare clone of the Git repository to the specified path.
        private func fetchBareRepository(
            provider: GitRepositoryProvider,
            specifier: RepositorySpecifier,
            to path: Basics.AbsolutePath
        ) throws {
            try provider.fetch(repository: specifier, to: path)
        }

        /// Validates that the directory contains a valid Git repository.
        private func validateDirectory(provider: GitRepositoryProvider, at path: Basics.AbsolutePath) throws {
            guard try provider.isValidDirectory(path) else {
                throw InternalError("Invalid directory at \(path)")
            }
        }

        /// Checks out the desired state (branch, tag, revision) in the working copy based on the requirement.
        ///
        /// - Throws: An error if no matching version is found in a version range, or if checkout fails.
        private func checkout(repository: WorkingCheckout) throws {
            switch self.requirement {
            case .exact(let version):
                try repository.checkout(tag: version.description)

            case .branch(let name):
                try repository.checkout(branch: name)

            case .revision(let revision):
                try repository.checkout(revision: .init(identifier: revision))

            case .range(let range):
                let tags = try repository.getTags()
                let versions = tags.compactMap { Version($0) }
                let filteredVersions = versions.filter { range.contains($0) }
                guard let latestVersion = filteredVersions.max() else {
                    throw InternalError("No tags found within the specified version range \(range)")
                }
                try repository.checkout(tag: latestVersion.description)
            }
        }
    }
}
