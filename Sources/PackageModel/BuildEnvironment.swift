//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A build environment with which to evaluate conditions.
public struct BuildEnvironment {
    /// The platform that is the target of the build
    public let platform: Platform
    /// Specifies whether this platform supports prebuilts
    public let supportsPrebuilts: Bool
    /// The build configuration for the build
    public let configuration: BuildConfiguration?

    public init(platform: Platform, supportsPrebuilts: Bool = false, configuration: BuildConfiguration? = nil) {
        self.platform = platform
        self.supportsPrebuilts = supportsPrebuilts
        self.configuration = configuration
    }
}
