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

public final class PrebuiltTarget: Module {
    public override class var typeDescription: String { "prebuiltTarget" }

    public let prebuilt: PrebuiltLibrary

    public init(prebuilt: PrebuiltLibrary) {
        self.prebuilt = prebuilt

        var buildSettings = BuildSettings.AssignmentTable()

        // Add modules path
        buildSettings.add(
            .init(values: [prebuilt.path.appending("Modules").pathString]),
            for: .SWIFT_INCLUDE_PATHS
        )

        // Add C header paths
        buildSettings.add(
            .init(values: prebuilt.includePath.map({
                prebuilt.checkoutPath.appending($0).pathString
            })),
            for: .HEADER_SEARCH_PATHS
        )

        // Add library
        buildSettings.add(.init(values: [prebuilt.libraryName]), for: .LINK_LIBRARIES)

        super.init(
            name: prebuilt.libraryName,
            type: .prebuilt,
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
