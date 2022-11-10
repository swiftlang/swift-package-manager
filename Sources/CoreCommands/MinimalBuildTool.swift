//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import Dispatch
import PackageModel
import Workspace

import struct SPMBuildCore.BuildSystemProvider
import struct TSCBasic.AbsolutePath
import var TSCBasic.stdoutStream
import enum TSCUtility.Diagnostics
import struct TSCUtility.Version

private class MinimalWorkspaceDelegate: WorkspaceDelegate {
    func willLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind) {}
    func didLoadManifest(packagePath: AbsolutePath, url: String, version: Version?, packageKind: PackageReference.Kind, manifest: Manifest?, diagnostics: [Basics.Diagnostic]) {}

    func willFetchPackage(package: PackageIdentity, packageLocation: String?, fetchDetails: PackageFetchDetails) {}
    func didFetchPackage(package: PackageIdentity, packageLocation: String?, result: Result<PackageFetchDetails, Error>, duration: DispatchTimeInterval) {}
    func fetchingPackage(package: PackageIdentity, packageLocation: String?, progress: Int64, total: Int64?) {}

    func willUpdateRepository(package: PackageIdentity, repository url: String) {}
    func didUpdateRepository(package: PackageIdentity, repository url: String, duration: DispatchTimeInterval) {}
    func dependenciesUpToDate() {}

    func willCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath) {}
    func didCreateWorkingCopy(package: PackageIdentity, repository url: String, at path: AbsolutePath) {}
    func willCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath) {}
    func didCheckOut(package: PackageIdentity, repository url: String, revision: String, at path: AbsolutePath) {}

    func removing(package: PackageIdentity, packageLocation: String?) {}

    func willResolveDependencies(reason: WorkspaceResolveReason) {}
    func willComputeVersion(package: PackageIdentity, location: String) {}
    func didComputeVersion(package: PackageIdentity, location: String, version: String, duration: DispatchTimeInterval) {}
    func resolvedFileChanged() {}

    func willDownloadBinaryArtifact(from url: String) {}
    func didDownloadBinaryArtifact(from url: String, result: Result<AbsolutePath, Error>, duration: DispatchTimeInterval) {}
    func downloadingBinaryArtifact(from url: String, bytesDownloaded: Int64, totalBytesToDownload: Int64?) {}
    func didDownloadAllBinaryArtifacts() {}
}

public struct SwiftMinimalBuildTool: SwiftCommand {
    @OptionGroup()
    public var globalOptions: GlobalOptions

    public func run(_ swiftTool: SwiftTool) throws {
        let buildSystem = try swiftTool.createBuildSystem(customOutputStream: TSCBasic.stdoutStream)

        do {
            try buildSystem.build(subset: .allExcludingTests)
        } catch _ as Diagnostics {
            throw ExitCode.failure
        }
    }

    public init() {}

    public func buildSystemProvider(_ swiftTool: SwiftTool) throws -> BuildSystemProvider {
        return try swiftTool.defaultBuildSystemProvider
    }

    public var workspaceDelegateProvider: WorkspaceDelegateProvider {
        return { _, _ , _  in
            MinimalWorkspaceDelegate()
        }
    }

    public var workspaceLoaderProvider: WorkspaceLoaderProvider {
        return { _, _ in
            fatalError("minimal build tool does not support loading workspaces")
        }
    }
}
