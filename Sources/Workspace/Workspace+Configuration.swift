/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018-2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import PackageFingerprint
import PackageGraph
import PackageLoading
import PackageModel
import PackageRegistry
import TSCBasic

import class TSCUtility.SimplePersistence
import protocol TSCUtility.SimplePersistanceProtocol

// MARK: - Location

extension Workspace {
    /// Workspace location configuration
    public struct Location {
        /// Path to working directory for this workspace.
        public var workingDirectory: AbsolutePath

        /// Path to store the editable versions of dependencies.
        public var editsDirectory: AbsolutePath

        /// Path to the Package.resolved file.
        public var resolvedVersionsFile: AbsolutePath

        /// Path to the local configuration directory
        public var localConfigurationDirectory: AbsolutePath

        /// Path to the shared configuration directory
        public var sharedConfigurationDirectory: AbsolutePath?

        /// Path to the shared security directory
        public var sharedSecurityDirectory: AbsolutePath?

        /// Path to the shared cache directory
        public var sharedCacheDirectory: AbsolutePath?

        // working directories

        /// Path to the repositories clones.
        public var repositoriesDirectory: AbsolutePath {
            self.workingDirectory.appending(component: "repositories")
        }

        /// Path to the repository checkouts.
        public var repositoriesCheckoutsDirectory: AbsolutePath {
            self.workingDirectory.appending(component: "checkouts")
        }

        /// Path to the registry downloads.
        public var registryDownloadDirectory: AbsolutePath {
            self.workingDirectory.appending(components: "registry", "downloads")
        }

        /// Path to the downloaded binary artifacts.
        public var artifactsDirectory: AbsolutePath {
            self.workingDirectory.appending(component: "artifacts")
        }

        // Path to temporary files related to running plugins in the workspace
        public var pluginWorkingDirectory: AbsolutePath {
            self.workingDirectory.appending(component: "plugins")
        }

        // config locations

        /// Path to the local mirrors configuration.
        public var localMirrorsConfigurationFile: AbsolutePath {
            // backwards compatibility
            if let customPath = ProcessEnv.vars["SWIFTPM_MIRROR_CONFIG"] {
                return AbsolutePath(customPath)
            }
            return DefaultLocations.mirrorsConfigurationFile(at: self.localConfigurationDirectory)
        }

        /// Path to the shared mirrors configuration.
        public var sharedMirrorsConfigurationFile: AbsolutePath? {
            self.sharedConfigurationDirectory.map { DefaultLocations.mirrorsConfigurationFile(at: $0) }
        }

        /// Path to the local registries configuration.
        public var localRegistriesConfigurationFile: AbsolutePath {
            DefaultLocations.registriesConfigurationFile(at: self.localConfigurationDirectory)
        }

        /// Path to the shared registries configuration.
        public var sharedRegistriesConfigurationFile: AbsolutePath? {
            self.sharedConfigurationDirectory.map { DefaultLocations.registriesConfigurationFile(at: $0) }
        }

        // security locations

        /// Path to the shared fingerprints directory.
        public var sharedFingerprintsDirectory: AbsolutePath? {
            self.sharedSecurityDirectory.map { $0.appending(component: "fingerprints") }
        }

        // cache locations

        /// Path to the shared manifests cache.
        public var sharedManifestsCacheDirectory: AbsolutePath? {
            self.sharedCacheDirectory.map { DefaultLocations.manifestsDirectory(at: $0) }
        }

        /// Path to the shared repositories cache.
        public var sharedRepositoriesCacheDirectory: AbsolutePath? {
            self.sharedCacheDirectory.map { $0.appending(component: "repositories") }
        }

        /// Path to the shared registry download cache.
        public var sharedRegistryDownloadsCacheDirectory: AbsolutePath? {
            self.sharedCacheDirectory.map { $0.appending(components: "registry", "downloads") }
        }

        /// Create a new workspace location.
        ///
        /// - Parameters:
        ///   - workingDirectory: Path to working directory for this workspace.
        ///   - editsDirectory: Path to store the editable versions of dependencies.
        ///   - resolvedVersionsFile: Path to the Package.resolved file.
        ///   - sharedSecurityDirectory: Path to the shared security directory.
        ///   - sharedCacheDirectory: Path to the shared cache directory.
        ///   - sharedConfigurationDirectory: Path to the shared configuration directory.
        public init(
            workingDirectory: AbsolutePath,
            editsDirectory: AbsolutePath,
            resolvedVersionsFile: AbsolutePath,
            localConfigurationDirectory: AbsolutePath,
            sharedConfigurationDirectory: AbsolutePath?,
            sharedSecurityDirectory: AbsolutePath?,
            sharedCacheDirectory: AbsolutePath?
        ) {
            self.workingDirectory = workingDirectory
            self.editsDirectory = editsDirectory
            self.resolvedVersionsFile = resolvedVersionsFile
            self.localConfigurationDirectory = localConfigurationDirectory
            self.sharedConfigurationDirectory = sharedConfigurationDirectory
            self.sharedSecurityDirectory = sharedSecurityDirectory
            self.sharedCacheDirectory = sharedCacheDirectory
        }

        /// Create a new workspace location.
        ///
        /// - Parameters:
        ///   - rootPath: Path to the root of the package, from which other locations can be derived.
        public init(forRootPackage rootPath: AbsolutePath, fileSystem: FileSystem) {
            self.init(
                workingDirectory: DefaultLocations.workingDirectory(forRootPackage: rootPath),
                editsDirectory: DefaultLocations.editsDirectory(forRootPackage: rootPath),
                resolvedVersionsFile: DefaultLocations.resolvedVersionsFile(forRootPackage: rootPath),
                localConfigurationDirectory: DefaultLocations.configurationDirectory(forRootPackage: rootPath),
                sharedConfigurationDirectory: fileSystem.swiftPMConfigurationDirectory,
                sharedSecurityDirectory: fileSystem.swiftPMSecurityDirectory,
                sharedCacheDirectory: fileSystem.swiftPMCacheDirectory
            )
        }
    }
}

// MARK: - Default locations

extension Workspace {
    /// Workspace default locations utilities
    public struct DefaultLocations {
        public static func workingDirectory(forRootPackage rootPath: AbsolutePath) -> AbsolutePath {
            rootPath.appending(component: ".build")
        }

        public static func editsDirectory(forRootPackage rootPath: AbsolutePath) -> AbsolutePath {
            rootPath.appending(component: "Packages")
        }

        public static func resolvedVersionsFile(forRootPackage rootPath: AbsolutePath) -> AbsolutePath {
            rootPath.appending(component: "Package.resolved")
        }

        public static func configurationDirectory(forRootPackage rootPath: AbsolutePath) -> AbsolutePath {
            rootPath.appending(components: ".swiftpm", "configuration")
        }

        public static func mirrorsConfigurationFile(forRootPackage rootPath: AbsolutePath) -> AbsolutePath {
            mirrorsConfigurationFile(at: self.configurationDirectory(forRootPackage: rootPath))
        }

        public static func mirrorsConfigurationFile(at path: AbsolutePath) -> AbsolutePath {
            path.appending(component: "mirrors.json")
        }

        public static func registriesConfigurationFile(forRootPackage rootPath: AbsolutePath) -> AbsolutePath {
            registriesConfigurationFile(at: self.configurationDirectory(forRootPackage: rootPath))
        }

        public static func registriesConfigurationFile(at path: AbsolutePath) -> AbsolutePath {
            path.appending(component: "registries.json")
        }

        public static func manifestsDirectory(at path: AbsolutePath) -> AbsolutePath {
            path.appending(component: "manifests")
        }
    }

    public static func migrateMirrorsConfiguration(from legacyPath: AbsolutePath, to newPath: AbsolutePath, observabilityScope: ObservabilityScope) throws -> AbsolutePath {
        if localFileSystem.isFile(legacyPath) {
            if localFileSystem.isSymlink(legacyPath) {
                let resolvedLegacyPath = resolveSymlinks(legacyPath)
                return try migrateMirrorsConfiguration(from: resolvedLegacyPath, to: newPath, observabilityScope: observabilityScope)
            } else if localFileSystem.isFile(newPath.parentDirectory) {
                observabilityScope.emit(warning: "Unable to migrate legacy mirrors configuration, because \(newPath.parentDirectory) already exists.")
            } else {
                observabilityScope.emit(warning: "Usage of \(legacyPath) has been deprecated. Please delete it and use the new \(newPath) instead.")
                if !localFileSystem.exists(newPath, followSymlink: false) {
                    try localFileSystem.createDirectory(newPath.parentDirectory, recursive: true)
                    try localFileSystem.copy(from: legacyPath, to: newPath)
                }
            }
        }
        return newPath.parentDirectory
    }
}

// MARK: - Authorization

extension Workspace.Configuration {
    public struct Authorization {
        public var netrc: Netrc
        public var keychain: Keychain

        public static var `default`: Self {
            #if canImport(Security)
            Self(netrc: .user, keychain: .enabled)
            #else
            Self(netrc: .user, keychain: .disabled)
            #endif
        }

        public init(netrc: Netrc, keychain: Keychain) {
            self.netrc = netrc
            self.keychain = keychain
        }

        public func makeAuthorizationProvider(fileSystem: FileSystem, observabilityScope: ObservabilityScope) throws -> AuthorizationProvider? {
            var providers = [AuthorizationProvider]()

            switch self.netrc {
            case .custom(let path):
                guard fileSystem.exists(path) else {
                    throw StringError("Did not find .netrc file at \(path).")
                }
                providers.append(try NetrcAuthorizationProvider(path: path, fileSystem: fileSystem))
            case .workspaceAndUser(let rootPath):
                // package/project "local" .netrc file, takes priority over user-level file
                let localPath = rootPath.appending(component: ".netrc")
                // user didn't tell us to explicitly use these .netrc files so be more lenient with errors
                if let localProvider = self.loadOptionalNetrc(fileSystem: fileSystem, path: localPath, observabilityScope: observabilityScope) {
                    providers.append(localProvider)
                }

                // user .netrc file (most typical)
                let userHomePath = fileSystem.homeDirectory.appending(component: ".netrc")
                // user didn't tell us to explicitly use these .netrc files so be more lenient with errors
                if let userHomeProvider = self.loadOptionalNetrc(fileSystem: fileSystem, path: userHomePath, observabilityScope: observabilityScope) {
                    providers.append(userHomeProvider)
                }
            case .user:
                // user .netrc file (most typical)
                let userHomePath = fileSystem.homeDirectory.appending(component: ".netrc")
                
                // user didn't tell us to explicitly use these .netrc files so be more lenient with errors
                if let userHomeProvider = self.loadOptionalNetrc(fileSystem: fileSystem, path: userHomePath, observabilityScope: observabilityScope) {
                    providers.append(userHomeProvider)
                }
            case .disabled:
                // noop
                break
            }

            switch self.keychain {
            case .enabled:
                #if canImport(Security)
                providers.append(KeychainAuthorizationProvider(observabilityScope: observabilityScope))
                #else
                throw InternalError("Keychain not supported on this platform")
                #endif
            case .disabled:
                // noop
                break
            }

            return providers.isEmpty ? .none : CompositeAuthorizationProvider(providers, observabilityScope: observabilityScope)
        }

        private func loadOptionalNetrc(
            fileSystem: FileSystem,
            path: AbsolutePath,
            observabilityScope: ObservabilityScope
        ) -> NetrcAuthorizationProvider? {
            guard fileSystem.exists(path) && fileSystem.isReadable(path) else {
                return .none
            }

            do {
                return try NetrcAuthorizationProvider(path: path, fileSystem: fileSystem)
            } catch {
                observabilityScope.emit(warning: "Failed to load .netrc file at \(path). Error: \(error)")
                return .none
            }
        }

        public enum Netrc {
            case disabled
            case custom(AbsolutePath)
            case workspaceAndUser(rootPath: AbsolutePath)
            case user
        }

        public enum Keychain {
            case disabled
            case enabled
        }
    }
}

// MARK: - Mirrors

extension Workspace.Configuration {
    public struct Mirrors {
        private let localMirrors: MirrorsStorage
        private let sharedMirrors: MirrorsStorage?
        private let fileSystem: FileSystem

        private var _mirrors: DependencyMirrors
        private let lock = Lock()

        /// The mirrors in this configuration
        public var mirrors: DependencyMirrors {
            self.lock.withLock {
                self._mirrors
            }
        }

        /// A convenience initializer for creating a workspace mirrors configuration for the given root
        /// package path.
        ///
        /// - Parameters:
        ///   - forRootPackage: The path for the root package.
        ///   - sharedMirrorFile: Path to the shared mirrors configuration file, defaults to the standard location.
        ///   - fileSystem: The file system to use.
        public init(
            forRootPackage rootPath: AbsolutePath,
            sharedMirrorFile: AbsolutePath?,
            fileSystem: FileSystem
        ) throws {
            let localMirrorConfigFile = Workspace.DefaultLocations.mirrorsConfigurationFile(forRootPackage: rootPath)
            try self.init(
                fileSystem: fileSystem,
                localMirrorsFile: localMirrorConfigFile,
                sharedMirrorsFile: sharedMirrorFile
            )
        }

        // deprecated 12/21
        @available(*, deprecated, message: "using init(fileSystem:localMirrorsFile:sharedMirrorsFile) instead")
        public init(localMirrorFile: AbsolutePath, sharedMirrorFile: AbsolutePath?, fileSystem: FileSystem) throws {
            try self.init(fileSystem: fileSystem, localMirrorsFile: localMirrorFile, sharedMirrorsFile: sharedMirrorFile)
        }

        /// Initialize the workspace mirrors configuration
        ///
        /// - Parameters:
        ///   - fileSystem: The file system to use.
        ///   - localMirrorsFile: Path to the workspace mirrors configuration file
        ///   - sharedMirrorsFile: Path to the shared mirrors configuration file, defaults to the standard location.
        public init(
            fileSystem: FileSystem,
            localMirrorsFile: AbsolutePath,
            sharedMirrorsFile: AbsolutePath?
        ) throws {
            self.localMirrors = .init(path: localMirrorsFile, fileSystem: fileSystem, deleteWhenEmpty: true)
            self.sharedMirrors = sharedMirrorsFile.map { .init(path: $0, fileSystem: fileSystem, deleteWhenEmpty: false) }
            self.fileSystem = fileSystem
            // computes the initial mirrors
            self._mirrors = DependencyMirrors()
            try self.computeMirrors()
        }

        @discardableResult
        public func applyLocal(handler: (inout DependencyMirrors) throws -> Void) throws -> DependencyMirrors {
            try self.localMirrors.apply(handler: handler)
            try self.computeMirrors()
            return self.mirrors
        }

        @discardableResult
        public func applyShared(handler: (inout DependencyMirrors) throws -> Void) throws -> DependencyMirrors {
            guard let sharedMirrors = self.sharedMirrors else {
                throw InternalError("shared mirrors not configured")
            }
            try sharedMirrors.apply(handler: handler)
            try self.computeMirrors()
            return self.mirrors
        }

        // mutating the state we hold since we are passing it by reference to the workspace
        // access should be done using a lock
        private func computeMirrors() throws {
            try self.lock.withLock {
                self._mirrors.removeAll()

                // prefer local mirrors to shared ones
                let local = try self.localMirrors.get()
                if !local.isEmpty {
                    self._mirrors.append(contentsOf: local)
                    return
                }

                // use shared if local was not found or empty
                if let shared = try self.sharedMirrors?.get(), !shared.isEmpty {
                    self._mirrors.append(contentsOf: shared)
                }
            }
        }
    }
}

extension Workspace.Configuration {
    public struct MirrorsStorage {
        private let path: AbsolutePath
        private let fileSystem: FileSystem
        private let deleteWhenEmpty: Bool

        public init(path: AbsolutePath, fileSystem: FileSystem, deleteWhenEmpty: Bool) {
            self.path = path
            self.fileSystem = fileSystem
            self.deleteWhenEmpty = deleteWhenEmpty
        }

        /// The mirrors in this configuration
        public func get() throws -> DependencyMirrors {
            guard self.fileSystem.exists(self.path) else {
                return DependencyMirrors()
            }
            return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .shared) {
                return DependencyMirrors(try Self.load(self.path, fileSystem: self.fileSystem))
            }
        }


        /// Apply a mutating handler on the mirrors in this configuration
        @discardableResult
        public func apply(handler: (inout DependencyMirrors) throws -> Void) throws -> DependencyMirrors {
            if !self.fileSystem.exists(self.path.parentDirectory) {
                try self.fileSystem.createDirectory(self.path.parentDirectory, recursive: true)
            }
            return try self.fileSystem.withLock(on: self.path.parentDirectory, type: .exclusive) {
                let mirrors = DependencyMirrors(try Self.load(self.path, fileSystem: self.fileSystem))
                var updatedMirrors = DependencyMirrors(mirrors.mapping)
                try handler(&updatedMirrors)
                if updatedMirrors != mirrors {
                    try Self.save(updatedMirrors.mapping, to: self.path, fileSystem: self.fileSystem, deleteWhenEmpty: self.deleteWhenEmpty)
                }
                return updatedMirrors
            }
        }

        private static func load(_ path: AbsolutePath, fileSystem: FileSystem) throws -> [String: String] {
            guard fileSystem.exists(path) else {
                return [:]
            }
            let data: Data = try fileSystem.readFileContents(path)
            let decoder = JSONDecoder.makeWithDefaults()
            let mirrors = try decoder.decode(MirrorsStorage.self, from: data)
            let mirrorsMap = Dictionary(mirrors.object.map({ ($0.original, $0.mirror) }), uniquingKeysWith: { first, _ in first })
            return mirrorsMap
        }

        private static func save(_ mirrors: [String: String], to path: AbsolutePath, fileSystem: FileSystem, deleteWhenEmpty: Bool) throws {
            if mirrors.isEmpty {
                if deleteWhenEmpty && fileSystem.exists(path)  {
                    // deleteWhenEmpty is a backward compatibility mode
                    return try fileSystem.removeFileTree(path)
                } else if !fileSystem.exists(path)  {
                    // nothing to do
                    return
                }
            }

            let encoder = JSONEncoder.makeWithDefaults()
            let mirrors = MirrorsStorage(version: 1, object: mirrors.map { .init(original: $0, mirror: $1) })
            let data = try encoder.encode(mirrors)
            if !fileSystem.exists(path.parentDirectory) {
                try fileSystem.createDirectory(path.parentDirectory, recursive: true)
            }
            try fileSystem.writeFileContents(path, data: data)
        }

        // structure is for backwards compatibility
        private struct MirrorsStorage: Codable {
            var version: Int
            var object: [Mirror]

            struct Mirror: Codable {
                var original: String
                var mirror: String
            }
        }
    }
}

// MARK: - Registries

extension Workspace.Configuration {
    public class Registries {
        private let localRegistries: RegistriesStorage
        private let sharedRegistries: RegistriesStorage?
        private let fileSystem: FileSystem

        private var _configuration = RegistryConfiguration()
        private let lock = Lock()

        /// The registry configuration
        public var configuration: RegistryConfiguration {
            self.lock.withLock {
                return self._configuration
            }
        }

        /// Initialize the workspace registries configuration
        ///
        /// - Parameters:
        ///   - fileSystem: The file system to use.
        ///   - localRegistriesFile: Path to the workspace registries configuration file
        ///   - sharedRegistriesFile: Path to the shared registries configuration file, defaults to the standard location.
        public init(
            fileSystem: FileSystem,
            localRegistriesFile: AbsolutePath,
            sharedRegistriesFile: AbsolutePath?
        ) throws {
            self.fileSystem = fileSystem
            self.localRegistries = .init(path: localRegistriesFile, fileSystem: fileSystem)
            self.sharedRegistries = sharedRegistriesFile.map { .init(path: $0, fileSystem: fileSystem) }
            try self.computeRegistries()
        }

        @discardableResult
        public func updateLocal(with handler: (inout RegistryConfiguration) throws -> Void) throws -> RegistryConfiguration {
            try self.localRegistries.update(with: handler)
            try self.computeRegistries()
            return self.configuration
        }

        @discardableResult
        public func updateShared(with handler: (inout RegistryConfiguration) throws -> Void) throws -> RegistryConfiguration {
            guard let sharedRegistries = self.sharedRegistries else {
                throw InternalError("shared registries not configured")
            }
            try sharedRegistries.update(with: handler)
            try self.computeRegistries()
            return self.configuration
        }

        // mutating the state we hold since we are passing it by reference to the workspace
        // access should be done using a lock
        private func computeRegistries() throws {
            try self.lock.withLock {
                var configuration = RegistryConfiguration()

                if let sharedConfiguration = try sharedRegistries?.load() {
                    configuration.merge(sharedConfiguration)
                }

                let localConfiguration = try localRegistries.load()
                configuration.merge(localConfiguration)

                self._configuration = configuration
            }
        }
    }
}

extension Workspace.Configuration {
    private struct RegistriesStorage {
        private let path: AbsolutePath
        private let fileSystem: FileSystem

        public init(path: AbsolutePath, fileSystem: FileSystem) {
            self.path = path
            self.fileSystem = fileSystem
        }

        public func load() throws -> RegistryConfiguration {
            guard fileSystem.exists(path) else {
                return RegistryConfiguration()
            }

            let data: Data = try fileSystem.readFileContents(path)
            let decoder = JSONDecoder.makeWithDefaults()
            return try decoder.decode(RegistryConfiguration.self, from: data)
        }

        public func save(_ configuration: RegistryConfiguration) throws {
            let encoder = JSONEncoder.makeWithDefaults()
            let data = try encoder.encode(configuration)

            if !fileSystem.exists(path.parentDirectory) {
                try fileSystem.createDirectory(path.parentDirectory, recursive: true)
            }
            try fileSystem.writeFileContents(path, bytes: ByteString(data), atomically: true)
        }

        @discardableResult
        public func update(with handler: (inout RegistryConfiguration) throws -> Void) throws -> RegistryConfiguration {
            let configuration = try load()
            var updatedConfiguration = configuration
            try handler(&updatedConfiguration)
            if updatedConfiguration != configuration {
                try save(updatedConfiguration)
            }

            return updatedConfiguration
        }
    }
}

// FIXME: better name
public struct WorkspaceConfiguration {
    /// Enables the dependencies resolver automatic version updates.  Disabled by default.
    /// When disabled the resolver does not attempt to update the dependencies as part of resolution.
    public var skipDependenciesUpdates: Bool

    /// Enables the dependencies resolver prefetching based on the resolved versions file.  Enabled by default.
    /// When disabled the resolver does not attempt to pre-fetch the dependencies based on the  resolved versions file.
    public var prefetchBasedOnResolvedFile: Bool

    /// File rules to determine resource handling behavior.
    public var additionalFileRules: [FileRuleDescription]

    /// Enables the shared dependencies cache. Enabled by default.
    public var sharedDependenciesCacheEnabled: Bool

    ///  Fingerprint checking mode. Defaults to warn.
    public var fingerprintCheckingMode: FingerprintCheckingMode

    ///  Attempt to transform source control based dependencies to registry ones
    public var sourceControlToRegistryDependencyTransformation: SourceControlToRegistryDependencyTransformation

    public init(
        skipDependenciesUpdates: Bool,
        prefetchBasedOnResolvedFile: Bool,
        additionalFileRules: [FileRuleDescription],
        sharedDependenciesCacheEnabled: Bool,
        fingerprintCheckingMode: FingerprintCheckingMode,
        sourceControlToRegistryDependencyTransformation: SourceControlToRegistryDependencyTransformation
    ) {
        self.skipDependenciesUpdates = skipDependenciesUpdates
        self.prefetchBasedOnResolvedFile = prefetchBasedOnResolvedFile
        self.additionalFileRules = additionalFileRules
        self.sharedDependenciesCacheEnabled = sharedDependenciesCacheEnabled
        self.fingerprintCheckingMode = fingerprintCheckingMode
        self.sourceControlToRegistryDependencyTransformation = sourceControlToRegistryDependencyTransformation
    }

    /// Default instance of WorkspaceConfiguration
    public static var `default`: Self {
        .init(
            skipDependenciesUpdates: false,
            prefetchBasedOnResolvedFile: true,
            additionalFileRules: [],
            sharedDependenciesCacheEnabled: true,
            fingerprintCheckingMode: .warn,
            sourceControlToRegistryDependencyTransformation: .disabled
        )
    }

    public enum SourceControlToRegistryDependencyTransformation {
        case disabled
        case identity
        case swizzle
    }
}

// MARK: - Deprecated 8/20201

extension Workspace {
    /// Manages a package workspace's configuration.
    // FIXME change into enum after deprecation grace period
    public final class Configuration {
        /// The path to the mirrors file.
        private let configFile: AbsolutePath?

        /// The filesystem to manage the mirrors file on.
        private var fileSystem: FileSystem?

        /// Persistence support.
        private let persistence: SimplePersistence?

        /// The schema version of the config file.
        ///
        /// * 1: Initial version.
        static let schemaVersion: Int = 1

        /// The mirrors.
        public private(set) var mirrors: DependencyMirrors = DependencyMirrors()

        @available(*, deprecated)
        public convenience init(path: AbsolutePath, fs: FileSystem = localFileSystem) throws {
            try self.init(path: path, fileSystem: fs)
        }

        /// Creates a new, persisted package configuration with a configuration file.
        /// - Parameters:
        ///   - path: A path to the configuration file.
        ///   - fileSystem: The filesystem on which the configuration file is located.
        /// - Throws: `StringError` if the configuration file is corrupted or malformed.
        @available(*, deprecated, message: "use Configuration.Mirrors instead")
        public init(path: AbsolutePath, fileSystem: FileSystem) throws {
            self.configFile = path
            self.fileSystem = fileSystem
            let persistence = SimplePersistence(
                fileSystem: fileSystem,
                schemaVersion: Self.schemaVersion,
                statePath: path,
                prettyPrint: true
            )

            do {
                self.persistence = persistence
                _ = try persistence.restoreState(self)
            } catch SimplePersistence.Error.restoreFailure(_, let error) {
                throw StringError("Configuration file is corrupted or malformed; fix or delete the file to continue: \(error)")
            }
        }

        /// Load the configuration from disk.
        @available(*, deprecated, message: "use Configuration.Mirrors instead")
        public func restoreState() throws {
            _ = try self.persistence?.restoreState(self)
        }

        /// Persists the current configuration to disk.
        ///
        /// If the configuration is empty, any persisted configuration file is removed.
        ///
        /// - Throws: If the configuration couldn't be persisted.
        @available(*, deprecated, message: "use Configuration.Mirrors instead")
        public func saveState() throws {
            guard let persistence = self.persistence else { return }

            // Remove the configuration file if there aren't any mirrors.
            if mirrors.isEmpty,
               let fileSystem = self.fileSystem,
               let configFile = self.configFile
            {
                return try fileSystem.removeFileTree(configFile)
            }

            try persistence.saveState(self)
        }
    }
}

@available(*, deprecated, message: "use Configuration.Mirrors instead")
extension Workspace.Configuration: JSONSerializable {
    public func toJSON() -> JSON {
        return mirrors.toJSON()
    }
}

@available(*, deprecated, message: "use Configuration.Mirrors instead")
extension Workspace.Configuration: SimplePersistanceProtocol {
    public func restore(from json: JSON) throws {
        self.mirrors = try DependencyMirrors(json: json)
    }
}
