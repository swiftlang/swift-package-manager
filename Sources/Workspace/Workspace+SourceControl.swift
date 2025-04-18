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

import TSCBasic

import struct Basics.AbsolutePath
import struct Basics.InternalError
import class Basics.ObservabilityScope
import struct Dispatch.DispatchTime
import enum PackageGraph.PackageRequirement
import class PackageGraph.ResolvedPackagesStore
import struct PackageModel.PackageReference
import struct SourceControl.Revision
import struct TSCUtility.Version

// FIXME: this mixes quite a bit of workspace logic with repository specific one
// need to better separate the concerns
extension Workspace {
    /// Create a local clone of the given `repository` checked out to `checkoutState`.
    ///
    /// If an existing clone is present, the repository will be reset to the
    /// requested revision, if necessary.
    ///
    /// - Parameters:
    ///   - package: The package to clone.
    ///   - checkoutState: The state to check out.
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    func checkoutRepository(
        package: PackageReference,
        at checkoutState: CheckoutState,
        observabilityScope: ObservabilityScope
    ) async throws -> AbsolutePath {
        let repository = try package.makeRepositorySpecifier()

        // first fetch the repository
        let checkoutPath = try await self.fetchRepository(
            package: package,
            at: checkoutState.revision,
            observabilityScope: observabilityScope
        )

        // Check out the given revision.
        let workingCopy = try self.repositoryManager.openWorkingCopy(at: checkoutPath)

        // Inform the delegate that we're about to start.
        delegate?.willCheckOut(
            package: package.identity,
            repository: repository.location.description,
            revision: checkoutState.description,
            at: checkoutPath
        )
        let start = DispatchTime.now()

        // Do mutable-immutable dance because checkout operation modifies the disk state.
        try fileSystem.chmod(.userWritable, path: checkoutPath, options: [.recursive, .onlyFiles])
        try workingCopy.checkout(revision: checkoutState.revision)
        try? fileSystem.chmod(.userUnWritable, path: checkoutPath, options: [.recursive, .onlyFiles])

        // Record the new state.
        observabilityScope.emit(
            debug: "adding '\(package.identity)' (\(package.locationString)) to managed dependencies",
            metadata: package.diagnosticsMetadata
        )
        try await self.state.add(
            dependency: .sourceControlCheckout(
                packageRef: package,
                state: checkoutState,
                subpath: checkoutPath.relative(to: self.location.repositoriesCheckoutsDirectory)
            )
        )
        try await self.state.save()

        // Inform the delegate that we're done.
        let duration = start.distance(to: .now())
        delegate?.didCheckOut(
            package: package.identity,
            repository: repository.location.description,
            revision: checkoutState.description,
            at: checkoutPath,
            duration: duration
        )
        observabilityScope
            .emit(debug: "`\(repository.location.description)` checked out at \(checkoutState.debugDescription)")

        return checkoutPath
    }

    func checkoutRepository(
        package: PackageReference,
        at resolutionStater: ResolvedPackagesStore.ResolutionState,
        observabilityScope: ObservabilityScope
    ) async throws -> AbsolutePath {
        switch resolutionStater {
        case .version(let version, revision: let revision) where revision != nil:
            return try await self.checkoutRepository(
                package: package,
                at: .version(version, revision: .init(identifier: revision!)), // nil checked above
                observabilityScope: observabilityScope
            )
        case .branch(let branch, revision: let revision):
            return try await self.checkoutRepository(
                package: package,
                at: .branch(name: branch, revision: .init(identifier: revision)),
                observabilityScope: observabilityScope
            )
        case .revision(let revision):
            return try await self.checkoutRepository(
                package: package,
                at: .revision(.init(identifier: revision)),
                observabilityScope: observabilityScope
            )
        default:
            throw InternalError("invalid resolution state: \(resolutionStater)")
        }
    }

    /// Fetch a given `package` and create a local checkout for it.
    ///
    /// This will first clone the repository into the canonical repositories
    /// location, if necessary, and then check it out from there.
    ///
    /// - Returns: The path of the local repository.
    /// - Throws: If the operation could not be satisfied.
    private func fetchRepository(
        package: PackageReference,
        at revision: Revision,
        observabilityScope: ObservabilityScope
    ) async throws -> AbsolutePath {
        let repository = try package.makeRepositorySpecifier()

        // If we already have it, fetch to update the repo from its remote.
        // also compare the location as it may have changed
        if let dependency = await self.state.dependencies[comparingLocation: package] {
            let checkoutPath = self.location.repositoriesCheckoutSubdirectory(for: dependency)

            // Make sure the directory is not missing (we will have to clone again if not).
            // This can become invalid if the build directory is moved.
            fetch: if self.fileSystem.isDirectory(checkoutPath) {
                // Fetch the checkout in case there are updates available.
                let workingCopy = try self.repositoryManager.openWorkingCopy(at: checkoutPath)

                // Ensure that the alternative object store is still valid.
                guard try self.repositoryManager.isValidWorkingCopy(workingCopy, for: repository) else {
                    observabilityScope
                        .emit(
                            debug: "working copy at '\(checkoutPath)' does not align with expected local path of '\(repository)'"
                        )
                    break fetch
                }

                // only update if necessary
                if !workingCopy.exists(revision: revision) {
                    // The fetch operation may update contents of the checkout,
                    // so we need to do mutable-immutable dance.
                    try self.fileSystem.chmod(.userWritable, path: checkoutPath, options: [.recursive, .onlyFiles])
                    try workingCopy.fetch()
                    try? self.fileSystem.chmod(.userUnWritable, path: checkoutPath, options: [.recursive, .onlyFiles])
                }

                return checkoutPath
            }
        }

        // If not, we need to get the repository from the checkouts.
        // FIXME: this should not block
        let handle = try await self.repositoryManager.lookup(
            package: package.identity,
            repository: repository,
            updateStrategy: .never,
            observabilityScope: observabilityScope,
            delegateQueue: .sharedConcurrent,
            callbackQueue: .sharedConcurrent
        )

        // Clone the repository into the checkouts.
        let checkoutPath = self.location.repositoriesCheckoutsDirectory.appending(component: repository.basename)

        // Remove any existing content at that path.
        try self.fileSystem.chmod(.userWritable, path: checkoutPath, options: [.recursive, .onlyFiles])
        try self.fileSystem.removeFileTree(checkoutPath)

        // Inform the delegate that we're about to start.
        self.delegate?.willCreateWorkingCopy(
            package: package.identity,
            repository: handle.repository.location.description,
            at: checkoutPath
        )
        let start = DispatchTime.now()

        // Create the working copy.
        _ = try handle.createWorkingCopy(at: checkoutPath, editable: false)

        // Inform the delegate that we're done.
        let duration = start.distance(to: .now())
        self.delegate?.didCreateWorkingCopy(
            package: package.identity,
            repository: handle.repository.location.description,
            at: checkoutPath,
            duration: duration
        )

        return checkoutPath
    }

    /// Removes the clone and checkout of the provided specifier.
    func removeRepository(dependency: ManagedDependency) throws {
        guard case .sourceControlCheckout = dependency.state else {
            throw InternalError("cannot remove repository for \(dependency) with state \(dependency.state)")
        }

        // Remove the checkout.
        let dependencyPath = self.location.repositoriesCheckoutSubdirectory(for: dependency)
        let workingCopy = try self.repositoryManager.openWorkingCopy(at: dependencyPath)
        guard !workingCopy.hasUncommittedChanges() else {
            throw WorkspaceDiagnostics.UncommittedChanges(repositoryPath: dependencyPath)
        }

        try self.fileSystem.chmod(.userWritable, path: dependencyPath, options: [.recursive, .onlyFiles])
        try self.fileSystem.removeFileTree(dependencyPath)

        // Remove the clone.
        try self.repositoryManager.remove(repository: dependency.packageRef.makeRepositorySpecifier())
    }
}

extension CheckoutState {
    var revision: Revision {
        switch self {
        case .revision(let revision):
            return revision
        case .version(_, let revision):
            return revision
        case .branch(_, let revision):
            return revision
        }
    }

    var isBranchOrRevisionBased: Bool {
        switch self {
        case .revision, .branch:
            return true
        case .version:
            return false
        }
    }

    var requirement: PackageRequirement {
        switch self {
        case .revision(let revision):
            return .revision(revision.identifier)
        case .version(let version, _):
            return .versionSet(.exact(version))
        case .branch(let branch, _):
            return .revision(branch)
        }
    }
}
