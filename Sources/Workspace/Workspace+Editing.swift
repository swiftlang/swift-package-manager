//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import PackageModel
import TSCBasic

import struct Basics.AbsolutePath
import class Basics.InMemoryFileSystem
import class Basics.ObservabilityScope
import struct Basics.RelativePath
import struct PackageGraph.PackageGraphRootInput
import struct SourceControl.Revision

extension Workspace {
    /// Edit implementation.
    func _edit(
        packageIdentity: String,
        path: AbsolutePath? = nil,
        revision: Revision? = nil,
        checkoutBranch: String? = nil,
        observabilityScope: ObservabilityScope
    ) async throws {
        // Look up the dependency and check if we can edit it.
        guard let dependency = await self.state.dependencies[.plain(packageIdentity)] else {
            observabilityScope.emit(.dependencyNotFound(packageName: packageIdentity))
            return
        }

        let observabilityScope = observabilityScope.makeChildScope(
            description: "editing package",
            metadata: dependency.packageRef.diagnosticsMetadata
        )

        let checkoutState: CheckoutState
        switch dependency.state {
        case .sourceControlCheckout(let _checkoutState):
            checkoutState = _checkoutState
        case .edited:
            observabilityScope.emit(error: "dependency '\(dependency.packageRef.identity)' already in edit mode")
            return
        case .fileSystem:
            observabilityScope.emit(error: "local dependency '\(dependency.packageRef.identity)' can't be edited")
            return
        case .registryDownload:
            observabilityScope.emit(error: "registry dependency '\(dependency.packageRef.identity)' can't be edited")
            return
        case .custom:
            observabilityScope.emit(error: "custom dependency '\(dependency.packageRef.identity)' can't be edited")
            return
        }

        // If a path is provided then we use it as destination. If not, we
        // use the folder with packageName inside editablesPath.
        let destination = path ?? self.location.editsDirectory.appending(component: packageIdentity)

        // If there is something present at the destination, we confirm it has
        // a valid manifest with name canonical location as the package we are trying to edit.
        if fileSystem.exists(destination) {
            // FIXME: this should not block
            let manifest = try await withCheckedThrowingContinuation { continuation in
                self.loadManifest(
                    packageIdentity: dependency.packageRef.identity,
                    packageKind: .fileSystem(destination),
                    packagePath: destination,
                    packageLocation: dependency.packageRef.locationString,
                    observabilityScope: observabilityScope,
                    completion: {
                      continuation.resume(with: $0)
                    }
                )
            }

            guard dependency.packageRef.canonicalLocation == manifest.canonicalPackageLocation else {
                return observabilityScope
                    .emit(
                        error: "package at '\(destination)' is \(dependency.packageRef.identity) but was expecting \(packageIdentity)"
                    )
            }

            // Emit warnings for branch and revision, if they're present.
            if let checkoutBranch {
                observabilityScope.emit(.editBranchNotCheckedOut(
                    packageName: packageIdentity,
                    branchName: checkoutBranch
                ))
            }
            if let revision {
                observabilityScope.emit(.editRevisionNotUsed(
                    packageName: packageIdentity,
                    revisionIdentifier: revision.identifier
                ))
            }
        } else {
            // Otherwise, create a checkout at the destination from our repository store.
            //
            // Get handle to the repository.
            // TODO: replace with async/await when available
            let repository = try dependency.packageRef.makeRepositorySpecifier()
            let handle = try await repositoryManager.lookup(
                package: dependency.packageRef.identity,
                repository: repository,
                updateStrategy: .never,
                observabilityScope: observabilityScope,
                delegateQueue: .sharedConcurrent,
                callbackQueue: .sharedConcurrent
            )
            let repo = try handle.open()

            // Do preliminary checks on branch and revision, if provided.
            if let branch = checkoutBranch, repo.exists(revision: Revision(identifier: branch)) {
                throw WorkspaceDiagnostics.BranchAlreadyExists(branch: branch)
            }
            if let revision, !repo.exists(revision: revision) {
                throw WorkspaceDiagnostics.RevisionDoesNotExist(revision: revision.identifier)
            }

            let workingCopy = try handle.createWorkingCopy(at: destination, editable: true)
            try workingCopy.checkout(revision: revision ?? checkoutState.revision)

            // Checkout to the new branch if provided.
            if let branch = checkoutBranch {
                try workingCopy.checkout(newBranch: branch)
            }
        }

        // For unmanaged dependencies, create the symlink under editables dir.
        if let path {
            try fileSystem.createDirectory(self.location.editsDirectory)
            // FIXME: We need this to work with InMem file system too.
            if !(fileSystem is InMemoryFileSystem) {
                let symLinkPath = self.location.editsDirectory.appending(component: packageIdentity)

                // Cleanup any existing symlink.
                if fileSystem.isSymlink(symLinkPath) {
                    try fileSystem.removeFileTree(symLinkPath)
                }

                // FIXME: We should probably just warn in case we fail to create
                // this symlink, which could happen if there is some non-symlink
                // entry at this location.
                try fileSystem.createSymbolicLink(symLinkPath, pointingAt: path, relative: false)
            }
        }

        // Remove the existing checkout.
        do {
            let oldCheckoutPath = self.location.repositoriesCheckoutSubdirectory(for: dependency)
            try fileSystem.chmod(.userWritable, path: oldCheckoutPath, options: [.recursive, .onlyFiles])
            try fileSystem.removeFileTree(oldCheckoutPath)
        }

        // Save the new state.
        try await self.state.add(
            dependency: dependency.edited(subpath: RelativePath(validating: packageIdentity), unmanagedPath: path)
        )
        try await self.state.save()
    }

    /// Unedit a managed dependency. See public API unedit(packageName:forceRemove:).
    func unedit(
        dependency: ManagedDependency,
        forceRemove: Bool,
        root: PackageGraphRootInput? = nil,
        observabilityScope: ObservabilityScope
    ) async throws {
        // Compute if we need to force remove.
        var forceRemove = forceRemove

        // If the dependency isn't in edit mode, we can't unedit it.
        guard case .edited(_, let unmanagedPath) = dependency.state else {
            throw WorkspaceDiagnostics
                .DependencyNotInEditMode(dependencyName: dependency.packageRef.identity.description)
        }

        // Set force remove to true for unmanaged dependencies.  Note that
        // this only removes the symlink under the editable directory and
        // not the actual unmanaged package.
        if unmanagedPath != nil {
            forceRemove = true
        }

        // Form the edit working repo path.
        let path = self.location.editSubdirectory(for: dependency)
        // Check for uncommitted and unpushed changes if force removal is off.
        if !forceRemove {
            let workingCopy = try repositoryManager.openWorkingCopy(at: path)
            guard !workingCopy.hasUncommittedChanges() else {
                throw WorkspaceDiagnostics.UncommittedChanges(repositoryPath: path)
            }
            guard try !workingCopy.hasUnpushedCommits() else {
                throw WorkspaceDiagnostics.UnpushedChanges(repositoryPath: path)
            }
        }
        // Remove the editable checkout from disk.
        if fileSystem.exists(path) {
            try fileSystem.removeFileTree(path)
        }
        // If this was the last editable dependency, remove the editables directory too.
        if fileSystem.exists(self.location.editsDirectory),
           try fileSystem.getDirectoryContents(self.location.editsDirectory).isEmpty
        {
            try fileSystem.removeFileTree(self.location.editsDirectory)
        }

        if case .edited(let basedOn, _) = dependency.state,
           case .sourceControlCheckout(let checkoutState) = basedOn?.state
        {
            // Restore the original checkout.
            //
            // The retrieve method will automatically update the managed dependency state.
            _ = try await self.checkoutRepository(
                package: dependency.packageRef,
                at: checkoutState,
                observabilityScope: observabilityScope
            )
        } else {
            // The original dependency was removed, update the managed dependency state.
            await self.state.remove(identity: dependency.packageRef.identity)
            try await self.state.save()
        }

        // Resolve the dependencies if workspace root is provided. We do this to
        // ensure the unedited version of this dependency is resolved properly.
        if let root {
            try await self._resolve(
                root: root,
                explicitProduct: .none,
                resolvedFileStrategy: .update(forceResolution: false),
                observabilityScope: observabilityScope
            )
        }
    }
}
