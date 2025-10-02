//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SourceControl
import TSCBasic

import class Basics.ObservabilityScope
import class Dispatch.DispatchQueue
import enum PackageFingerprint.FingerprintCheckingMode
import enum PackageGraph.ContainerUpdateStrategy
import protocol PackageGraph.PackageContainer
import protocol PackageGraph.PackageContainerProvider
import struct PackageModel.PackageReference

// MARK: - Package container provider

extension Workspace: PackageContainerProvider {
    public func getContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> any PackageContainer {
        switch package.kind {
        // If the container is local, just create and return a local package container.
        case .root, .fileSystem:
            let container = try FileSystemPackageContainer(
                package: package,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                manifestLoader: self.manifestLoader,
                currentToolsVersion: self.currentToolsVersion,
                fileSystem: self.fileSystem,
                observabilityScope: observabilityScope
            )
            return container
        // Resolve the container using the repository manager.
        case .localSourceControl, .remoteSourceControl:
            let repositorySpecifier = try package.makeRepositorySpecifier()
            let handle = try await self.repositoryManager.lookup(
                package: package.identity,
                repository: repositorySpecifier,
                updateStrategy: updateStrategy.repositoryUpdateStrategy,
                observabilityScope: observabilityScope
            )

            // Open the repository.
            //
            // FIXME: Do we care about holding this open for the lifetime of the container.
            let repository = try await handle.open()
            let result = try SourceControlPackageContainer(
                package: package,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                repositorySpecifier: repositorySpecifier,
                repository: repository,
                manifestLoader: self.manifestLoader,
                currentToolsVersion: self.currentToolsVersion,
                fingerprintStorage: self.fingerprints,
                fingerprintCheckingMode: FingerprintCheckingMode
                    .map(self.configuration.fingerprintCheckingMode),
                observabilityScope: observabilityScope
            )
            return result
        // Resolve the container using the registry
        case .registry:
            let container = RegistryPackageContainer(
                package: package,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                registryClient: self.registryClient,
                manifestLoader: self.manifestLoader,
                currentToolsVersion: self.currentToolsVersion,
                observabilityScope: observabilityScope
            )
            return container
        }
    }
}
