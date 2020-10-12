/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The configuration of the build environment.
public enum BuildConfiguration: String, CaseIterable, Codable {
    case debug
    case release

    public var dirname: String {
        switch self {
            case .debug: return "debug"
            case .release: return "release"
        }
    }
}
