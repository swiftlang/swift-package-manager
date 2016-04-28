/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: ErrorProtocol {
    case ObsoleteGitVersion
    case UnknownGitError
    case UnicodeDecodingError
    case UnicodeEncodingError
    case CouldNotCreateFile(path: String)
    case FileDoesNotExist(path: String)
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ObsoleteGitVersion:
            return "Git 2.0 or higher is required. Please update git and retry."
        case .UnknownGitError:
            return "Failed to invoke git command. Please try updating git"
        case .UnicodeDecodingError: return "Could not decode input file into unicode"
        case .UnicodeEncodingError: return "Could not encode string into unicode"
        case .CouldNotCreateFile(let path): return "Could not create file: \(path)"
        case .FileDoesNotExist(let path): return "File does not exist: \(path)"
        }
    }
}
