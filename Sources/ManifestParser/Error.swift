/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: ErrorType {
    case NoManifest(String)
    case InvalidManifest(String, errors: [String], data: String)
    case ManifestModuleNotFound(String)
    case NoSources(String)
}

public enum InvalidSourcesLayoutError: ErrorType {
    case MultipleSourceFolders([String])
    case ConflictingSources(String)
}

extension InvalidSourcesLayoutError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .MultipleSourceFolders(let folders):
            return "Multiple source folders are found: \(folders). There should be only one source folder in the package."
        case .ConflictingSources(let folder):
            return "There should be no source files under: \(folder)."
        }
    }
}