/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Configuration: String {
    case debug, release

    public var dirname: String {
        switch self {
            case .debug: return "debug"
            case .release: return "release"
        }
    }
}

// Ext stuff
// FIXME: Find a place to put this.

import PackageExtension

public class SwiftPackageManager: PackageManager {
    public static let `default` = SwiftPackageManager()

    public private(set) var buildRules: [String: BuildRule.Type]

    private init() {
        buildRules = [:]
    }

    public func registerBuildRule(name: String, implementation: BuildRule.Type) {
        buildRules[name] = implementation
    }
}

// Ext stuff
