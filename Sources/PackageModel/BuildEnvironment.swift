/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A build environment with which to evaluation conditions.
public struct BuildEnvironment: Codable {
    public let platform: Platform
    public let configuration: BuildConfiguration

    public init(platform: Platform, configuration: BuildConfiguration) {
        self.platform = platform
        self.configuration = configuration
    }
}
