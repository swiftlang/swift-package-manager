/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageLoading
import PackageModel
import PackageRegistry
import SourceControl

import TSCBasic
import TSCUtility

import Dispatch

public final class RegistryPackageContainer {
    public var identifier: PackageReference

    let mirrors: DependencyMirrors

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    /// The current tools version in use.
    let currentToolsVersion: ToolsVersion

    public let registryManager: RegistryManager

    private(set) var versionsDescendingCache: [Version] = []
    private var manifestsCache = ThreadSafeKeyValueStore<Version, Manifest>()
    private var toolsVersionsCache = ThreadSafeKeyValueStore<Version, ToolsVersion>()
    private var validToolsVersionsCache = ThreadSafeKeyValueStore<Version, Bool>()

    private init(
        _ identifier: PackageReference,
        mirrors: DependencyMirrors,
        registryManager: RegistryManager,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion
    ) {
        self.identifier = identifier
        self.mirrors = mirrors
        self.registryManager = registryManager
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion
    }

    static func create(
        for identifier: PackageReference,
        mirrors: DependencyMirrors,
        registryManager: RegistryManager,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        completion: @escaping (Result<RegistryPackageContainer, Error>) -> Void
    ) {
        let container = RegistryPackageContainer(identifier,
                                                 mirrors: mirrors,
                                                 registryManager: registryManager,
                                                 manifestLoader: manifestLoader,
                                                 toolsVersionLoader: toolsVersionLoader,
                                                 currentToolsVersion: currentToolsVersion)

        registryManager.fetchVersions(of: identifier) { result in
            switch result {
            case .success(let versionsWithDuplicates):
                container.versionsDescendingCache = Set(versionsWithDuplicates).sorted(by: >)
                completion(.success(container))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func manifest(for version: Version) throws -> Manifest {
        try manifestsCache.memoize(version) {
            try tsc_await { registryManager.fetchManifest(for: version, of: identifier, using: manifestLoader, completion: $0) }
        }
    }
}

extension RegistryPackageContainer: PackageContainer {
    private func isValidToolsVersion(_ toolsVersion: ToolsVersion) -> Bool {
        do {
            try toolsVersion.validateToolsVersion(currentToolsVersion, packagePath: "")
            return true
        } catch {
            return false
        }
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        return (try? isValidToolsVersion(toolsVersion(for: version))) ?? false
    }

    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        return try self.manifest(for: version).toolsVersion
    }

    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        return versionsDescendingCache.lazy.filter({
            // If we have the result cached, return that.
            if let result = self.validToolsVersionsCache[$0] {
                return result
            }

            // Otherwise, compute and cache the result.
            let isValid = (try? self.toolsVersion(for: $0)).flatMap(self.isValidToolsVersion(_:)) ?? false
            self.validToolsVersionsCache[$0] = isValid
            return isValid
        })
    }

    public func versions(filter isIncluded: (Version) -> Bool) throws -> AnySequence<Version>
    {
        AnySequence(versionsDescendingCache
                            .filter(isIncluded)
                            .lazy
                            .filter { version in
            self.validToolsVersionsCache.memoize(version) {
                self.isToolsVersionCompatible(at: version)
            }
        })
    }

    public func versionsDescending() throws -> [Version] {
        self.versionsDescendingCache
    }

    public func versionsAscending() throws -> [Version] {
        self.versionsDescendingCache.reversed()
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        return try self.manifest(for: version).dependencyConstraints(productFilter: productFilter, mirrors: mirrors)
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        throw RegistryError.invalidOperation
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        return []
    }

    public func getUpdatedIdentifier(at boundVersion: BoundVersion) throws -> PackageReference {
        guard case .version(let version) = boundVersion else {
            assertionFailure("Unexpected type requirement \(boundVersion)")
            return identifier
        }

        return try identifier.with(newName: self.manifest(for: version).name)
    }
}

// MARK: -

public class RegistryPackageContainerProvider {
    let manifestLoader: ManifestLoaderProtocol
    let mirrors: DependencyMirrors
    let currentToolsVersion: ToolsVersion
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    private var containerCache = ThreadSafeKeyValueStore<PackageReference, PackageContainer>()

    public init(
        mirrors: DependencyMirrors = DependencyMirrors(),
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        toolsVersionLoader: ToolsVersionLoaderProtocol = ToolsVersionLoader()
    ) {
        self.mirrors = mirrors
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.toolsVersionLoader = toolsVersionLoader
    }
}

extension RegistryPackageContainerProvider: PackageContainerProvider {
    public func getContainer(
        for identifier: PackageReference,
        skipUpdate: Bool,
        on queue: DispatchQueue,
        completion: @escaping (Result<PackageContainer, Swift.Error>) -> Void
    ) {
        assert(identifier.kind == .remote)

        if let container = containerCache[identifier] {
            queue.async {
                completion(.success(container))
            }
        } else {
            RegistryManager.discover(for: identifier, on: queue) { result in
                switch result {
                case .success(let registryManager):
                    RegistryPackageContainer.create(
                        for: identifier,
                        mirrors: self.mirrors,
                        registryManager: registryManager,
                        manifestLoader: self.manifestLoader,
                        toolsVersionLoader: self.toolsVersionLoader,
                        currentToolsVersion: self.currentToolsVersion
                    ) { result in
                        switch result {
                        case .success(let container):
                            self.containerCache[identifier] = container

                            queue.async {
                                completion(.success(container))
                            }
                        case .failure(let error):
                            queue.async {
                                completion(.failure(error))
                            }
                        }
                    }
                case .failure(let error):
                    queue.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
}

extension RegistryPackageContainer: CustomStringConvertible {
    public var description: String {
        return "RegistryPackageContainer(\(identifier.repository.url.debugDescription))"
    }
}
