/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import PackageModel
import TSCBasic

public struct MockPackage {
    public let name: String
    public let platforms: [PlatformDescription]
    public let location: Location
    public let targets: [MockTarget]
    public let products: [MockProduct]
    public let dependencies: [MockDependency]
    public let versions: [String?]
    // FIXME: This should be per-version.
    public let toolsVersion: ToolsVersion?

    public init(
        name: String,
        platforms: [PlatformDescription] = [],
        path: String? = nil,
        targets: [MockTarget],
        products: [MockProduct],
        dependencies: [MockDependency] = [],
        versions: [String?] = [],
        toolsVersion: ToolsVersion? = nil
    ) {
        self.name = name
        self.platforms = platforms
        self.location = .fileSystem(path: RelativePath(path ?? name))
        self.targets = targets
        self.products = products
        self.dependencies = dependencies
        self.versions = versions
        self.toolsVersion = toolsVersion
    }

    public init(
        name: String,
        platforms: [PlatformDescription] = [],
        url: String,
        targets: [MockTarget],
        products: [MockProduct],
        dependencies: [MockDependency] = [],
        versions: [String?] = [],
        toolsVersion: ToolsVersion? = nil
    ) {
        self.name = name
        self.platforms = platforms
        self.location = .sourceControl(url: URL(string: url)!)
        self.targets = targets
        self.products = products
        self.dependencies = dependencies
        self.versions = versions
        self.toolsVersion = toolsVersion
    }

    public static func genericPackage1(named name: String) throws -> MockPackage {
        return MockPackage(
            name: name,
            targets: [
                try MockTarget(name: name),
            ],
            products: [
                MockProduct(name: name, targets: [name]),
            ],
            versions: ["1.0.0"]
        )
    }

    public enum Location {
        case fileSystem(path: RelativePath)
        case sourceControl(url: Foundation.URL)
    }
}
