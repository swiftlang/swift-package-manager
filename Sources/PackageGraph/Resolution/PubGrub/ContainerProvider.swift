//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import PackageModel
import TSCBasic

/// An utility class around PackageContainerProvider that allows "prefetching" the containers
/// in parallel. The basic idea is to kick off container fetching before starting the resolution
/// by using the list of URLs from the Package.resolved file.
final class ContainerProvider {
    /// The actual package container provider.
    private let underlying: PackageContainerProvider

    /// Whether to perform update (git fetch) on existing cloned repositories or not.
    private let skipUpdate: Bool

    /// `Package.resolved` file representation.
    private let resolvedPackages: ResolvedPackagesStore.ResolvedPackages

    /// Observability scope to emit diagnostics with
    private let observabilityScope: ObservabilityScope

    //// Store cached containers
    private var containersCache = ThreadSafeKeyValueStore<PackageReference, PubGrubPackageContainer>()

    //// Store prefetches synchronization
    private var prefetches = ThreadSafeKeyValueStore<PackageReference, DispatchGroup>()

    init(
        provider underlying: PackageContainerProvider,
        skipUpdate: Bool,
        resolvedPackages: ResolvedPackagesStore.ResolvedPackages,
        observabilityScope: ObservabilityScope
    ) {
        self.underlying = underlying
        self.skipUpdate = skipUpdate
        self.resolvedPackages = resolvedPackages
        self.observabilityScope = observabilityScope
    }

    /// Get a cached container for the given identifier, asserting / throwing if not found.
    func getCachedContainer(for package: PackageReference) throws -> PubGrubPackageContainer {
        guard let container = self.containersCache[package] else {
            throw InternalError("container for \(package.identity) expected to be cached")
        }
        return container
    }

    /// Get the container for the given identifier, loading it if necessary.
    func getContainer(
        for package: PackageReference,
        completion: @escaping (Result<PubGrubPackageContainer, Error>) -> Void
    ) {
        // Return the cached container, if available.
        if let container = self.containersCache[comparingLocation: package] {
            return completion(.success(container))
        }

        if let prefetchSync = self.prefetches[package] {
            // If this container is already being prefetched, wait for that to complete
            prefetchSync.notify(queue: .sharedConcurrent) {
                if let container = self.containersCache[comparingLocation: package] {
                    // should be in the cache once prefetch completed
                    return completion(.success(container))
                } else {
                    // if prefetch failed, remove from list of prefetches and try again
                    self.prefetches[package] = nil
                    return self.getContainer(for: package, completion: completion)
                }
            }
        } else {
            // Otherwise, fetch the container from the provider
            self.underlying.getContainer(
                for: package,
                updateStrategy: self.skipUpdate ? .never : .always, // TODO: make this more elaborate
                observabilityScope: self.observabilityScope.makeChildScope(description: "getting package container", metadata: package.diagnosticsMetadata),
                on: .sharedConcurrent
            ) { result in
                let result = result.tryMap { container -> PubGrubPackageContainer in
                    let pubGrubContainer = PubGrubPackageContainer(underlying: container, resolvedPackages: self.resolvedPackages)
                    // only cache positive results
                    self.containersCache[package] = pubGrubContainer
                    return pubGrubContainer
                }
                completion(result)
            }
        }
    }

    /// Starts prefetching the given containers.
    func prefetch(containers identifiers: [PackageReference]) {
        // Process each container.
        for identifier in identifiers {
            var needsFetching = false
            self.prefetches.memoize(identifier) {
                let group = DispatchGroup()
                group.enter()
                needsFetching = true
                return group
            }
            if needsFetching {
                self.underlying.getContainer(
                    for: identifier,
                    updateStrategy: self.skipUpdate ? .never : .always, // TODO: make this more elaborate
                    observabilityScope: self.observabilityScope.makeChildScope(description: "prefetching package container", metadata: identifier.diagnosticsMetadata),
                    on: .sharedConcurrent
                ) { result in
                    defer { self.prefetches[identifier]?.leave() }
                    // only cache positive results
                    if case .success(let container) = result {
                        self.containersCache[identifier] = PubGrubPackageContainer(underlying: container, resolvedPackages: self.resolvedPackages)
                    }
                }
            }
        }
    }
}

extension ThreadSafeKeyValueStore where Key == PackageReference, Value == PubGrubPackageContainer {
    subscript(comparingLocation package: PackageReference) -> PubGrubPackageContainer? {
        if let container = self[package], container.package.equalsIncludingLocation(package) {
            return container
        }
        return .none
    }
}
