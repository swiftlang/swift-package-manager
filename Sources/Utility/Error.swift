/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: Swift.Error {
    case obsoleteGitVersion
    case unknownGitError
    case unicodeDecodingError
    case unicodeEncodingError
    case couldNotCreateFile(path: String)
    case fileDoesNotExist(path: String)
    case invalidPlatformPath
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .obsoleteGitVersion:
            return "Git 2.0 or higher is required. Please update git and retry"
        case .unknownGitError:
            return "Failed to invoke git command. Please try updating git."
        case .unicodeDecodingError: return "Could not decode input file into unicode."
        case .unicodeEncodingError: return "Could not encode string into unicode."
        case .couldNotCreateFile(let path): return "Could not create file: \(path)."
        case .fileDoesNotExist(let path): return "File does not exist: \(path)."
        case .invalidPlatformPath: return "Invalid platform path."
        }
    }
}
