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

import struct Basics.AbsolutePath

public final class SystemLibraryTarget: Target {

    /// The name of pkgConfig file, if any.
    public let pkgConfig: String?

    /// List of system package providers, if any.
    public let providers: [SystemPackageProviderDescription]?

    /// True if this system library should become implicit target
    /// dependency of its dependent packages.
    public let isImplicit: Bool

    public init(
        name: String,
        path: AbsolutePath,
        isImplicit: Bool = true,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil
    ) {
        let sources = Sources(paths: [], root: path)
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.isImplicit = isImplicit
        super.init(
            name: name,
            type: .systemModule,
            path: sources.root,
            sources: sources,
            dependencies: [],
            packageAccess: false,
            buildSettings: .init(),
            buildSettingsDescription: [],
            pluginUsages: [],
            usesUnsafeFlags: false
        )
    }
}
