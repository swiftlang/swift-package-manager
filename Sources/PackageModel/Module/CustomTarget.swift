//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import struct Basics.AbsolutePath
import struct Basics.StringError
import TSCBasic

/// A custom target is generally a target without Swift or Clang source
/// where plugins define how build products are produced.
public final class CustomTarget: Module {
    public override class var typeDescription: String { "customTarget" }

    public init(
        name: String,
        path: AbsolutePath,
        sources: Sources,
        resources: [Resource],
        dependencies: [Module.Dependency],
        buildSettings: BuildSettings.AssignmentTable,
        buildSettingsDescription: [TargetBuildSettingDescription.Setting],
    ) {
        super.init(
            name: name,
            type: .custom,
            path: path,
            sources: sources,
            resources: resources,
            dependencies: dependencies,
            packageAccess: true,
            buildSettings: buildSettings,
            buildSettingsDescription: buildSettingsDescription,
            pluginUsages: [], // TODO: these no longer do anything, they're in the dependencies
            usesUnsafeFlags: false,
            implicit: false
        )
    }
}

/// External targets are custom targets where the source outside the package
/// either on a local path or fetched from a remote location.
public final class ExternalTarget: Module {
    public override class var typeDescription: String { "externalTarget" }

    public enum Location {
        case localPath(AbsolutePath)
        case remoteArchive(url: URL, checksum: String)
    }

    public init(
        name: String,
        location: Location,
        dependencies: [Module.Dependency],
        buildSettings: BuildSettings.AssignmentTable,
        buildSettingsDescription: [TargetBuildSettingDescription.Setting],
    ) {
        guard case let .localPath(path) = location else {
            fatalError("TODO")
        }

        super.init(
            name: name,
            type: .custom,
            path: path,
            sources: .init(paths: [], root: path),
            resources: [],
            dependencies: dependencies,
            packageAccess: true,
            buildSettings: buildSettings,
            buildSettingsDescription: buildSettingsDescription,
            pluginUsages: [],
            usesUnsafeFlags: false,
            implicit: false
        )
    }
}

/// Prebuilt targets is a custom target that represents a prebuilt library that is downloaded and added to the build.
/// The build system will copy the library to the build products directory and add build settings to be able to use it.
public final class PrebuiltTarget: Module {
    public override class var typeDescription: String { "prebuiltTarget" }

    public let prebuilt: PrebuiltLibrary

    public init(prebuilt: PrebuiltLibrary) {
        self.prebuilt = prebuilt

        // Set the public include path to the Modules dir in the prebuilts
        // and to the include path from the prebuilts source checkouts directory.
        var buildSettings = BuildSettings.AssignmentTable()

        // Add modules path
        buildSettings.add(
            .init(values: [prebuilt.path.appending("Modules").pathString]),
            for: .SWIFT_INCLUDE_PATHS
        )

        // Add C header paths
        buildSettings.add(
            .init(values: prebuilt.includePath.map({ prebuilt.checkoutPath.appending($0).pathString })),
            for: .HEADER_SEARCH_PATHS
        )

        // Add library setting. Build system is responsible for copying it to the
        // build products directory to pick it up.
        buildSettings.add(.init(values: [prebuilt.libraryName]), for: .LINK_LIBRARIES)

        super.init(
            name: prebuilt.libraryName,
            type: .custom,
            path: prebuilt.path,
            sources: .init(paths: [], root: prebuilt.path),
            dependencies: [],
            packageAccess: false,
            buildSettings: buildSettings,
            buildSettingsDescription: [],
            pluginUsages: [],
            usesUnsafeFlags: false,
            implicit: false
        )
    }
}
