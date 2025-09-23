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

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageFingerprint
import struct PackageModel.PackageIdentity
import PackageRegistry
import PackageSigning
import SourceControl
@_spi(PackageRefactor) import SwiftRefactor
import TSCBasic
import TSCUtility
import Workspace

/// A protocol representing a generic template fetcher for Swift package templates.
///
/// Conforming types are responsible for retrieving a package template from a specific source,
/// such as a local directory, a Git repository, or a remote registry. The retrieved template
/// must be available on the local file system in order to infer package type.
///
/// - Note: The returned path is an **absolute file system path** pointing to the **root directory**
///   of the fetched template. This path must reference a fully resolved and locally accessible
///   directory that contains the template's contents, ready for use by any consumer.
///
/// Example sources might include:
/// - Local file paths (e.g. `/Users/username/Templates/MyTemplate`)
/// -  Git repositories, either on disk or by HTTPS  or SSH.
/// - Registry-resolved template directories
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
            self.fetcher = GitTemplateFetcher(
                source: url,
                requirement: requirement,
                swiftCommandState: swiftCommandState
            )

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
                "Template path must be specified for local templates."
            case .missingGitURLOrRequirement:
                "Missing Git URL or requirement for git template."
            case .missingRegistryIdentityOrRequirement:
                "Missing registry package identity or requirement."
            case .missingTemplateType:
                "Missing --template-type."
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

/// Fetches a Swift package template from a Git repository based on a specified requirement for initial package type inference.
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

    let swiftCommandState: SwiftCommandState

    /// Fetches the repository and returns the path to the checked-out working copy.
    ///
    /// - Returns: A path to the directory containing the fetched template.
    /// - Throws: Any error encountered during repository fetch, checkout, or validation.
    func fetch() async throws -> Basics.AbsolutePath {
        try await withTemporaryDirectory(removeTreeOnDeinit: false) { tempDir in
            let bareCopyPath = tempDir.appending(component: "bare-copy")
            let workingCopyPath = tempDir.appending(component: "working-copy")

            try await self.cloneBareRepository(into: bareCopyPath)

            defer {
                try? FileManager.default.removeItem(at: bareCopyPath.asURL)
            }

            try self.validateBareRepository(at: bareCopyPath)

            try FileManager.default.createDirectory(
                atPath: workingCopyPath.pathString,
                withIntermediateDirectories: true
            )

            let repository = try createWorkingCopy(fromBare: bareCopyPath, at: workingCopyPath)

            try self.checkout(repository: repository)

            return workingCopyPath
        }
    }

    /// Clones a bare git repository.
    ///
    /// - Throws: An error is thrown if fetching fails.
    private func cloneBareRepository(into path: Basics.AbsolutePath) async throws {
        let url = SourceControlURL(source)
        let repositorySpecifier = RepositorySpecifier(url: url)
        let provider = GitRepositoryProvider()
        do {
            try await provider.fetch(repository: repositorySpecifier, to: path)
        } catch {
            if self.isPermissionError(error) {
                throw GitTemplateFetcherError.authenticationRequired(source: self.source, error: error)
            }
            throw GitTemplateFetcherError.cloneFailed(source: self.source)
        }
    }

    /// Function to determine if its a specifc SSHPermssionError
    ///
    ///  - Returns: A boolean determining if it is either a permission error, or not.
    private func isPermissionError(_ error: Error) -> Bool {
        let errorString = String(describing: error).lowercased()
        return errorString.contains("permission denied")
    }

    /// Validates that the directory contains a valid Git repository.
    ///
    ///  - Parameters:
    ///     - path: the path where the git repository is located
    ///  - Throws: .invalidRepositoryDirectory(path: path) if the path does not contain a valid git directory.
    private func validateBareRepository(at path: Basics.AbsolutePath) throws {
        let provider = GitRepositoryProvider()
        guard try provider.isValidDirectory(path) else {
            throw GitTemplateFetcherError.invalidRepositoryDirectory(path: path)
        }
    }

    /// Creates a working copy from a bare directory.
    ///
    /// - Throws: .createWorkingCopyFailed(path: workingCopyPath, underlyingError: error) if the provider failed to create a working copy from a bare repository
    private func createWorkingCopy(
        fromBare barePath: Basics.AbsolutePath,
        at workingCopyPath: Basics.AbsolutePath
    ) throws -> WorkingCheckout {
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
        case .exact(let versionString):
            try repository.checkout(tag: versionString)

        case .branch(let name):
            try repository.checkout(branch: name)

        case .revision(let revision):
            try repository.checkout(revision: .init(identifier: revision))

        case .range(let lowerBound, let upperBound):
            let tags = try repository.getTags()
            let versions = tags.compactMap { Version($0) }

            guard let lowerVersion = Version(lowerBound),
                  let upperVersion = Version(upperBound)
            else {
                throw GitTemplateFetcherError.invalidVersionRange(lowerBound: lowerBound, upperBound: upperBound)
            }

            let versionRange = lowerVersion ..< upperVersion
            let filteredVersions = versions.filter { versionRange.contains($0) }
            guard let latestVersion = filteredVersions.max() else {
                throw GitTemplateFetcherError.noMatchingTagInVersionRange(
                    lowerBound: lowerBound,
                    upperBound: upperBound
                )
            }
            try repository.checkout(tag: latestVersion.description)

        case .rangeFrom(let versionString):
            let tags = try repository.getTags()
            let versions = tags.compactMap { Version($0) }

            guard let lowerVersion = Version(versionString) else {
                throw GitTemplateFetcherError.invalidVersion(versionString)
            }

            let filteredVersions = versions.filter { $0 >= lowerVersion }
            guard let latestVersion = filteredVersions.max() else {
                throw GitTemplateFetcherError.noMatchingTagFromVersion(versionString)
            }
            try repository.checkout(tag: latestVersion.description)
        }
    }

    enum GitTemplateFetcherError: Error, LocalizedError, Equatable {
        case cloneFailed(source: String)
        case invalidRepositoryDirectory(path: Basics.AbsolutePath)
        case createWorkingCopyFailed(path: Basics.AbsolutePath, underlyingError: Error)
        case checkoutFailed(requirement: PackageDependency.SourceControl.Requirement, underlyingError: Error)
        case noMatchingTagInVersionRange(lowerBound: String, upperBound: String)
        case noMatchingTagFromVersion(String)
        case invalidVersionRange(lowerBound: String, upperBound: String)
        case invalidVersion(String)
        case authenticationRequired(source: String, error: Error)

        var errorDescription: String? {
            switch self {
            case .cloneFailed(let source):
                "Failed to clone repository from '\(source)'"
            case .invalidRepositoryDirectory(let path):
                "Invalid Git repository at path: \(path.pathString)"
            case .createWorkingCopyFailed(let path, let error):
                "Failed to create working copy at '\(path)': \(error.localizedDescription)"
            case .checkoutFailed(let requirement, let error):
                "Failed to checkout using requirement '\(requirement)': \(error.localizedDescription)"
            case .noMatchingTagInVersionRange(let lowerBound, let upperBound):
                "No Git tags found within version range \(lowerBound)..<\(upperBound)"
            case .noMatchingTagFromVersion(let version):
                "No Git tags found from version \(version) or later"
            case .invalidVersionRange(let lowerBound, let upperBound):
                "Invalid version range: \(lowerBound)..<\(upperBound)"
            case .invalidVersion(let version):
                "Invalid version string: \(version)"
            case .authenticationRequired(let source, let error):
                "Authentication required for '\(source)'. \(error)"
            }
        }

        static func == (lhs: GitTemplateFetcherError, rhs: GitTemplateFetcherError) -> Bool {
            lhs.errorDescription == rhs.errorDescription
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
    let swiftCommandState: SwiftCommandState

    /// The package identifier of the package in registry
    let packageIdentity: String

    /// The registry requirement used to determine which version to fetch.
    let requirement: PackageDependency.Registry.Requirement

    /// Performs the registry fetch by downloading and extracting a source archive for initial package type inference
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
                version: self.version,
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
    ///
    ///  - Throws: .invalidVersionString if the requirement string does not correspond to a valid semver format version.
    private var version: Version {
        get throws {
            switch self.requirement {
            case .exact(let versionString):
                guard let version = Version(versionString) else {
                    throw RegistryConfigError.invalidVersionString(version: versionString)
                }
                return version
            case .range(_, let upperBound):
                guard let version = Version(upperBound) else {
                    throw RegistryConfigError.invalidVersionString(version: upperBound)
                }
                return version
            case .rangeFrom(let versionString):
                guard let version = Version(versionString) else {
                    throw RegistryConfigError.invalidVersionString(version: versionString)
                }
                return version
            }
        }
    }

    /// Resolves the registry configuration from shared SwiftPM configuration.
    ///
    /// - Returns: Registry configuration to use for fetching packages.
    /// - Throws: If configurations  are missing or unreadable.
    static func getRegistriesConfig(_ swiftCommandState: SwiftCommandState, global: Bool) throws -> Workspace
        .Configuration.Registries
    {
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

        /// Indicates that the conversion from string to Version failed
        case invalidVersionString(version: String)

        var errorDescription: String? {
            switch self {
            case .invalidVersionString(let version):
                "Invalid version string: \(version)"
            case .failedToLoadConfiguration(let file, let underlyingError):
                """
                Failed to load registry configuration from '\(file.pathString)': \
                \(underlyingError.localizedDescription)
                """
            }
        }
    }
}
