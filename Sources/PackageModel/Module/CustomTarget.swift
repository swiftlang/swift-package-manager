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
import struct Basics.StringError
import TSCBasic

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
            pluginUsages: [],
            usesUnsafeFlags: false,
            implicit: false
        )
    }
}
