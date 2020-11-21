/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch

import PackageLoading
import PackageModel
import PackageRegistry
import SourceControl

import TSCBasic
import TSCUtility

public class CompositePackageContainerProvider: PackageContainerProvider {
    let manifestLoader: ManifestLoaderProtocol
    let repositoryManager: RepositoryManager
    let mirrors: DependencyMirrors

    /// The tools version currently in use. Only the container versions less than and equal to this will be provided by
    /// the container.
    let currentToolsVersion: ToolsVersion

    /// The tools version loader.
    let toolsVersionLoader: ToolsVersionLoaderProtocol

    let fileSystem: FileSystem

    /// Create a repository-based package provider.
    ///
    /// - Parameters:
    ///   - repositoryManager: The repository manager responsible for providing repositories.
    ///   - manifestLoader: The manifest loader instance.
    ///   - currentToolsVersion: The current tools version in use.
    ///   - toolsVersionLoader: The tools version loader.
    public init(
        repositoryManager: RepositoryManager,
        mirrors: DependencyMirrors = DependencyMirrors(),
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        toolsVersionLoader: ToolsVersionLoaderProtocol = ToolsVersionLoader(),
        fileSystem: FileSystem = localFileSystem
    ) {
        self.repositoryManager = repositoryManager
        self.mirrors = mirrors
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.toolsVersionLoader = toolsVersionLoader
        self.fileSystem = fileSystem
    }

    public func getContainer(
        for reference: PackageReference,
        skipUpdate: Bool,
        on queue: DispatchQueue,
        completion: @escaping (Result<PackageContainer, Swift.Error>) -> Void
    ) {
        // For remote package references, attempt to load from registry before falling back to respository access.
        if reference.kind == .remote {
            let provider = RegistryPackageContainerProvider(mirrors: mirrors, manifestLoader: manifestLoader, currentToolsVersion: currentToolsVersion, toolsVersionLoader: toolsVersionLoader)
            provider.getContainer(for: reference, skipUpdate: skipUpdate, on: queue) { result in
                guard case .failure = result else {
                    return queue.async {
                        completion(result)
                    }
                }

                let provider = RepositoryPackageContainerProvider(repositoryManager: self.repositoryManager, mirrors: self.mirrors, manifestLoader: self.manifestLoader, currentToolsVersion: self.currentToolsVersion, toolsVersionLoader: self.toolsVersionLoader)
                provider.getContainer(for: reference, skipUpdate: skipUpdate, on: queue, completion: completion)
            }
        } else {
            let provider = LocalPackageContainerProvider(mirrors: self.mirrors, manifestLoader: self.manifestLoader, currentToolsVersion: self.currentToolsVersion, toolsVersionLoader: self.toolsVersionLoader, fileSystem: self.fileSystem)
            provider.getContainer(for: reference, skipUpdate: skipUpdate, on: queue, completion: completion)
        }
    }
}
