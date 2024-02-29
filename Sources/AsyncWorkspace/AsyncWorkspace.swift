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
import struct TSCUtility.Version
import struct Foundation.URL
import protocol PackageFingerprint.PackageFingerprintStorage
import struct PackageModel.PackageIdentity
import struct PackageRegistry.RegistryConfiguration
import protocol PackageSigning.PackageSigningEntityStorage
import class Workspace.Workspace

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
