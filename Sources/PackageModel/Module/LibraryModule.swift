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

import struct Basics.AbsolutePath

/// A library target which has no sources of its own.
public final class LibraryModule: Module {
    public override class var typeDescription: String { "LibraryTarget" }

    public init(
        name: String,
        type libraryType: ProductType.LibraryType,
        dependencies: [Module.Dependency],
        packageAccess: Bool,
        buildSettings: BuildSettings.AssignmentTable = .init(),
        buildSettingsDescription: [TargetBuildSettingDescription.Setting] = [],
        pluginUsages: [PluginUsage] = [],
        usesUnsafeFlags: Bool = false
    ) {
        super.init(
            name: name,
            type: .libraryAggregate(libraryType: libraryType),
            path: AbsolutePath.root,
            sources: Sources(paths: [], root: AbsolutePath.root),
            dependencies: dependencies,
            packageAccess: packageAccess,
            buildSettings: buildSettings,
            buildSettingsDescription: buildSettingsDescription,
            pluginUsages: pluginUsages,
            usesUnsafeFlags: usesUnsafeFlags,
            implicit: false
        )
    }

    public static func unsupportedMessage(_ moduleName: String) -> String {
        "library target '\(moduleName)' is only supported by the 'swiftbuild' build system"
    }
}
