/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Error: ErrorType {
    case InvalidModuleName(String)
    case InvalidManifest(String, errors: [String], data: String)
    case NoManifest(String)
    case ManifestTargetNotFound(String)
    case InvalidDependencyGraph(String)
    case InvalidSourcesLayout(path: String, type: InvalidSourcesLayoutError)
    case UpdateRequired(String)

    case GitCloneFailure(String, String)
}


extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case NoManifest(let path):
            return "No Package.swift file found at: \(path)"
        case InvalidModuleName(let name):
            return "Invalid c99 module name: \(name)"
        case InvalidManifest(let path, let errors, _):
            return "The manifest at \(path) is invalid.\n" + errors.joinWithSeparator("\n")
        case ManifestTargetNotFound(let target):
            return "The manifest describes a target that cannot be found in your source tree: \(target)"
        case InvalidDependencyGraph(let package):
            return "The dependency graph could not be satisfied (\(package))"
        case InvalidSourcesLayout(let path, let errorType):
            return "Your source structure is not supported due to invalid sources layout: \(path). \(errorType)"
        case UpdateRequired(let package):
            return "The dependency graph could not be satisfied because an update to `\(package)' is required"
        case .GitCloneFailure(let url, let dstdir):
            return "Failed to clone \(url) to \(dstdir)"
        }
    }
}

public enum InvalidSourcesLayoutError {
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