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

package import _Concurrency
private import protocol Basics.AuthorizationProvider
private import class Basics.Cancellator
private import protocol Basics.FileSystem
internal import struct Basics.Version
internal import struct Foundation.URL
private import protocol PackageFingerprint.PackageFingerprintStorage
internal import struct PackageModel.PackageIdentity
private import struct PackageRegistry.RegistryConfiguration
private import protocol PackageSigning.PackageSigningEntityStorage
private import class Workspace.Workspace

package actor AsyncWorkspace {
    private let workspace: Workspace
    private var state = State.initial

    package var events: AsyncStream<Workspace.Event>

    enum State {
        case initial
    }

    init(workspace: Workspace, state: AsyncWorkspace.State = State.initial, events: AsyncStream<Workspace.Event>) {
        self.workspace = workspace
        self.state = state
        self.events = events
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
        version: Version
    ) -> UntrustedPackageContinuation

    func onUntrustedRegistryPackage(
        registryURL: URL,
        package: PackageModel.PackageIdentity,
        version: Version
    ) -> UntrustedPackageContinuation
}
