/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: Swift.Error {
    case obsoleteGitVersion
    case unknownGitError
    case invalidPlatformPath
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .obsoleteGitVersion:
            return "Git 2.0 or higher is required. Please update git and retry"
        case .unknownGitError:
            return "Failed to invoke git command. Please try updating git"
        case .invalidPlatformPath: return "Invalid platform path"
        }
    }
}
