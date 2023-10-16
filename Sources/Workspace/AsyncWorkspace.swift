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

import _Concurrency
import protocol Basics.AuthorizationProvider
import class Basics.Cancellator
import protocol Basics.FileSystem
import struct Foundation.URL
import protocol PackageFingerprint.PackageFingerprintStorage
import struct PackageModel.PackageIdentity
import struct PackageRegistry.RegistryConfiguration
import protocol PackageSigning.PackageSigningEntityStorage
import struct TSCUtility.Version

public actor AsyncWorkspace {
    private let workspace: Workspace
    private var state = State.initial

    public var events: AsyncStream<Workspace.Event>

    enum State {
        case initial
    }

    init(
        // core
        fileSystem: any FileSystem,
        location: Workspace.Location,
        authorizationProvider: (any AuthorizationProvider)?,
        registryAuthorizationProvider: (any AuthorizationProvider)?,
        configuration: WorkspaceConfiguration?,
        cancellator: Cancellator?,
        initializationWarningHandler: ((String) -> Void)?,
        // optional customization, primarily designed for testing but also used in some cases by libSwiftPM consumers
        customRegistriesConfiguration: RegistryConfiguration?,
        customFingerprints: (any PackageFingerprintStorage)?,
        customSigningEntities: (any PackageSigningEntityStorage)?,
        skipSignatureValidation: Bool,
        customMirrors: DependencyMirrors?,
        customToolsVersion: ToolsVersion?,
        customHostToolchain: UserToolchain?,
        customManifestLoader: ManifestLoaderProtocol?,
        customPackageContainerProvider: PackageContainerProvider?,
        customRepositoryManager: RepositoryManager?,
        customRepositoryProvider: RepositoryProvider?,
        customRegistryClient: RegistryClient?,
        customBinaryArtifactsManager: CustomBinaryArtifactsManager?,
        customIdentityResolver: IdentityResolver?,
        customDependencyMapper: DependencyMapper?,
        customChecksumAlgorithm: HashAlgorithm?
    ) {
        let (stream, continuation) = AsyncStream<Workspace.Event>.makeStream()
        self.events = stream
        self.workspace = Workspace(
            fileSystem: fileSystem,
            location: location,
            authorizationProvider: authorizationProvider,
            registryAuthorizationProvider: registryAuthorizationProvider,
            configuration: configuration,
            cancellator: cancellator,
            initializationWarningHandler: initializationWarningHandler,
            customRegistriesConfiguration: customRegistriesConfiguration,
            customFingerprints: customFingerprints,
            customSigningEntities: customSigningEntities,
            skipSignatureValidation: skipSignatureValidation,
            customMirrors: customMirrors,
            customToolsVersion: customToolsVersion,
            customHostToolchain: customHostToolchain,
            customManifestLoader: customManifestLoader,
            customPackageContainerProvider: customPackageContainerProvider,
            customRepositoryManager: customRepositoryManager,
            customRepositoryProvider: customRepositoryProvider,
            customRegistryClient: customRegistryClient,
            customBinaryArtifactsManager: customBinaryArtifactsManager,
            customIdentityResolver: customIdentityResolver,
            customDependencyMapper: customDependencyMapper,
            customChecksumAlgorithm: customChecksumAlgorithm,
            delegate: nil,
            eventsContinuation: continuation
        )
    }
}

enum UntrustedPackageContinuation {
    case proceed
    case stop
}

/// Handlers for unsigned and untrusted registry based dependencies
protocol WorkspaceRegistryDelegate: AnyActor {
    func onUnsignedRegistryPackage(
        registryURL: URL,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version
    ) -> UntrustedPackageContinuation

    func onUntrustedRegistryPackage(
        registryURL: URL,
        package: PackageModel.PackageIdentity,
        version: TSCUtility.Version
    ) -> UntrustedPackageContinuation
}
