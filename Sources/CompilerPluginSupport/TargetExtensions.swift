//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(PackageDescriptionInternal) import PackageDescription

public extension Target {
    @available(_PackageDescription, introduced: 5.9)
    static func macro(
        name: String,
        dependencies: [Dependency] = [],
        path: String? = nil,
        exclude: [String] = [],
        sources: [String]? = nil,
        packageAccess: Bool = true,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil,
        plugins: [PluginUsage]? = nil
    ) -> Target {
        return Target(name: name,
                      dependencies: dependencies,
                      path: path,
                      exclude: exclude,
                      sources: sources,
                      publicHeadersPath: nil,
                      type: .macro,
                      packageAccess: packageAccess,
                      swiftSettings: swiftSettings,
                      linkerSettings: linkerSettings,
                      plugins: plugins)
    }
}
