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

import Basics

public class ExternalTarget: Module {
    public init(
        name: String,
        path: AbsolutePath,
        buildSettings: BuildSettings.AssignmentTable,
        buildSettingsDescription: [TargetBuildSettingDescription.Setting]
    ) {
        super.init(
            name: name,
            type: .external,
            path: path,
            sources: .init(paths: [], root: path),
            dependencies: [],
            packageAccess: false,
            buildSettings: buildSettings,
            buildSettingsDescription: buildSettingsDescription,
            usesUnsafeFlags: false,
            implicit: false
        )
    }
}
