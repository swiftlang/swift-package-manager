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

//TODO: needs review
import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageFingerprint
import PackageModel
import PackageRegistry
import PackageSigning
import SourceControl
import TSCBasic
import TSCUtility
import Workspace

/// A protocol representing a generic package template fetcher.
///
/// Conforming types encapsulate the logic to retrieve a template from a given source,
/// such as a local path, Git repository, or registry. The template is expected to be
/// returned as an absolute path to its location on the file system.
protocol TemplateFetcher {
    func fetch() async throws -> Basics.AbsolutePath
}

/// Resolves the path to a Swift package template based on the specified template source.
///
/// This struct determines how to obtain the template, whether from:
/// - A local directory (`.local`)
/// - A Git repository (`.git`)
/// - A Swift package registry (`.registry`)
///
/// It abstracts the underlying fetch logic using a strategy pattern via the `TemplateFetcher` protocol.
///
/// Usage:
/// ```swift
/// let resolver = try TemplatePathResolver(...)
/// let templatePath = try await resolver.resolve()
/// ```
struct TemplatePathResolver {
    let fetcher: TemplateFetcher

    /// Initializes a TemplatePathResolver with the given source and options.
    ///
    /// - Parameters:
    ///   - source: The type of template source (`local`, `git`, or `registry`).
    ///   - templateDirectory: Local path if using `.local` source.
    ///   - templateURL: Git URL if using `.git` source.
    ///   - sourceControlRequirement: Versioning or branch details for Git.
    ///   - registryRequirement: Versioning requirement for registry.
    ///   - packageIdentity: Package name/identity used with registry templates.
    ///   - swiftCommandState: Command state to access file system and config.
    ///
    /// - Throws: `StringError` if any required parameter is missing.
    init(
        source: InitTemplatePackage.TemplateSource?,
        templateDirectory: Basics.AbsolutePath?,
        templateURL: String?,
        sourceControlRequirement: PackageDependency.SourceControl.Requirement?,
        registryRequirement: PackageDependency.Registry.Requirement?,
        packageIdentity: String?,
        swiftCommandState: SwiftCommandState
    ) throws {
        switch source {
        case .local:
            guard let path = templateDirectory else {
                throw TemplatePathResolverError.missingLocalTemplatePath
            }
            self.fetcher = LocalTemplateFetcher(path: path)

        case .git:
            guard let url = templateURL, let requirement = sourceControlRequirement else {
                throw TemplatePathResolverError.missingGitURLOrRequirement
            }
            self.fetcher = GitTemplateFetcher(source: url, requirement: requirement)

        case .registry:
            guard let identity = packageIdentity, let requirement = registryRequirement else {
                throw TemplatePathResolverError.missingRegistryIdentityOrRequirement
            }
            self.fetcher = RegistryTemplateFetcher(
                swiftCommandState: swiftCommandState,
                packageIdentity: identity,
                requirement: requirement
            )

        case .none:
            throw TemplatePathResolverError.missingTemplateType
        }
    }

    /// Resolves the template path by executing the underlying fetcher.
    ///
    /// - Returns: Absolute path to the downloaded or located template directory.
    /// - Throws: Any error encountered during fetch.
    func resolve() async throws -> Basics.AbsolutePath {
        try await self.fetcher.fetch()
    }

    /// Errors thrown by `TemplatePathResolver` during initialization.
    enum TemplatePathResolverError: LocalizedError, Equatable {
        case missingLocalTemplatePath
        case missingGitURLOrRequirement
        case missingRegistryIdentityOrRequirement
        case missingTemplateType

        var errorDescription: String? {
            switch self {
            case .missingLocalTemplatePath:
                return "Template path must be specified for local templates."
            case .missingGitURLOrRequirement:
                return "Missing Git URL or requirement for git template."
            case .missingRegistryIdentityOrRequirement:
                return "Missing registry package identity or requirement."
            case .missingTemplateType:
                return "Missing --template-type."
            }
        }
    }
}

/// Fetcher implementation for local file system templates.
///
/// Simply returns the provided path as-is, assuming it exists and is valid.
struct LocalTemplateFetcher: TemplateFetcher {
    let path: Basics.AbsolutePath

    func fetch() async throws -> Basics.AbsolutePath {
        self.path
    }
}

/// Fetches a Swift package template from a Git repository based on a specified requirement.
///
/// Supports:
/// - Checkout by tag (exact version)
/// - Checkout by branch
/// - Checkout by specific revision
/// - Checkout the highest version within a version range
///
/// The template is cloned into a temporary directory, checked out, and returned.

struct GitTemplateFetcher: TemplateFetcher {
    /// The Git URL of the remote repository.
    let source: String

    /// The source control requirement used to determine which version/branch/revision to check out.
    let requirement: PackageDependency.SourceControl.Requirement

    /// Fetches the repository and returns the path to the checked-out working copy.
    ///
    /// - Returns: A path to the directory containing the fetched template.
    /// - Throws: Any error encountered during repository fetch, checkout, or validation.

    /// Fetches a bare clone of the Git repository to the specified path.
    func fetch() async throws -> Basics.AbsolutePath {
        try withTemporaryDirectory(removeTreeOnDeinit: false) { tempDir in
            let bareCopyPath = tempDir.appending(component: "bare-copy")
            let workingCopyPath = tempDir.appending(component: "working-copy")


            try cloneBareRepository(into: bareCopyPath)
            try validateBareRepository(at: bareCopyPath)

            try FileManager.default.createDirectory(
                atPath: workingCopyPath.pathString,
                withIntermediateDirectories: true
            )

            let repository = try createWorkingCopy(fromBare: bareCopyPath, at: workingCopyPath)
            try FileManager.default.removeItem(at: bareCopyPath.asURL)

            try checkout(repository: repository)

            return workingCopyPath
        }
    }

    /// Clones a bare git repository.
    ///
    /// - Throws: An error is thrown if fetching fails.
    private func cloneBareRepository(into path: Basics.AbsolutePath) throws {
        let url = SourceControlURL(source)
        let repositorySpecifier = RepositorySpecifier(url: url)
        let provider = GitRepositoryProvider()
        do {
            try provider.fetch(repository: repositorySpecifier, to: path)
        } catch {
            throw GitTemplateFetcherError.cloneFailed(source: source, underlyingError: error)
        }
    }

    /// Validates that the directory contains a valid Git repository.
    private func validateBareRepository(at path: Basics.AbsolutePath) throws {
        let provider = GitRepositoryProvider()
        guard try provider.isValidDirectory(path) else {
            throw GitTemplateFetcherError.invalidRepositoryDirectory(path: path)
        }
    }

    /// Creates a working copy from a bare directory.
    ///
    /// - Throws: An error.
    private func createWorkingCopy(fromBare barePath: Basics.AbsolutePath, at workingCopyPath: Basics.AbsolutePath) throws -> WorkingCheckout {
        let url = SourceControlURL(source)
        let repositorySpecifier = RepositorySpecifier(url: url)
        let provider = GitRepositoryProvider()
        do {
            return try provider.createWorkingCopyFromBare(
                repository: repositorySpecifier,
                sourcePath: barePath,
                at: workingCopyPath,
                editable: true
            )
        } catch {
            throw GitTemplateFetcherError.createWorkingCopyFailed(path: workingCopyPath, underlyingError: error)
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
                throw GitTemplateFetcherError.noMatchingTagInRange(range)
            }
            try repository.checkout(tag: latestVersion.description)
        }
    }

    enum GitTemplateFetcherError: Error, LocalizedError {
            case cloneFailed(source: String, underlyingError: Error)
            case invalidRepositoryDirectory(path: Basics.AbsolutePath)
            case createWorkingCopyFailed(path: Basics.AbsolutePath, underlyingError: Error)
            case checkoutFailed(requirement: PackageDependency.SourceControl.Requirement, underlyingError: Error)
            case noMatchingTagInRange(Range<Version>)

            var errorDescription: String? {
                switch self {
                case .cloneFailed(let source, let error):
                    return "Failed to clone repository from '\(source)': \(error.localizedDescription)"
                case .invalidRepositoryDirectory(let path):
                    return "Invalid Git repository at path: \(path.pathString)"
                case .createWorkingCopyFailed(let path, let error):
                    return "Failed to create working copy at '\(path)': \(error.localizedDescription)"
                case .checkoutFailed(let requirement, let error):
                    return "Failed to checkout using requirement '\(requirement)': \(error.localizedDescription)"
                case .noMatchingTagInRange(let range):
                    return "No Git tags found within version range \(range)"
                }
            }
        }

}

/// Fetches a Swift package template from a package registry.
///
/// Downloads the source archive for the specified package and version.
/// Extracts it to a temporary directory and returns the path.
///
/// Supports:
/// - Exact version
/// - Upper bound of a version range (e.g., latest version within a range)
struct RegistryTemplateFetcher: TemplateFetcher {
    /// The swiftCommandState of the current process.
    /// Used to get configurations and authentication needed to get package from registry
    let swiftCommandState: SwiftCommandState

    /// The package identifier of the package in registry
    let packageIdentity: String
    /// The registry requirement used to determine which version to fetch.
    let requirement: PackageDependency.Registry.Requirement

    /// Performs the registry fetch by downloading and extracting a source archive.
    ///
    /// - Returns: Absolute path to the extracted template directory.
    /// - Throws: If registry configuration is invalid or the download fails.

    func fetch() async throws -> Basics.AbsolutePath {
        try await withTemporaryDirectory(removeTreeOnDeinit: false) { tempDir in
            let config = try Self.getRegistriesConfig(self.swiftCommandState, global: true)
            let auth = try swiftCommandState.getRegistryAuthorizationProvider()

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

            let identity = PackageIdentity.plain(self.packageIdentity)

            let dest = tempDir.appending(component: self.packageIdentity)
            try await registryClient.downloadSourceArchive(
                package: identity,
                version: version,
                destinationPath: dest,
                progressHandler: nil,
                timeout: nil,
                fileSystem: self.swiftCommandState.fileSystem,
                observabilityScope: self.swiftCommandState.observabilityScope
            )

            return dest
        }
    }

    /// Extract the version from the registry requirements
    private var version: Version {
        switch requirement {
        case .exact(let v): return v
        case .range(let r): return r.upperBound
        }
    }


    /// Resolves the registry configuration from shared SwiftPM configuration.
    ///
    /// - Returns: Registry configuration to use for fetching packages.
    /// - Throws: If configurations  are missing or unreadable.
    private static func getRegistriesConfig(_ swiftCommandState: SwiftCommandState, global: Bool) throws -> Workspace
        .Configuration.Registries {
        let sharedFile = Workspace.DefaultLocations
            .registriesConfigurationFile(at: swiftCommandState.sharedConfigurationDirectory)
        do {
            return try .init(
                fileSystem: swiftCommandState.fileSystem,
                localRegistriesFile: .none,
                sharedRegistriesFile: sharedFile
            )
        } catch {
            throw RegistryConfigError.failedToLoadConfiguration(file: sharedFile, underlyingError: error)
        }
    }

    /// Errors that can occur while loading Swift package registry configuration.
    enum RegistryConfigError: Error, LocalizedError {
        /// Indicates the configuration file could not be loaded.
        case failedToLoadConfiguration(file: Basics.AbsolutePath, underlyingError: Error)

        var errorDescription: String? {
            switch self {
            case .failedToLoadConfiguration(let file, let underlyingError):
                return """
                Failed to load registry configuration from '\(file.pathString)': \
                \(underlyingError.localizedDescription)
                """
            }
        }
    }

}
