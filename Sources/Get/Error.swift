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

    case InvalidModuleName(String)

    case ManifestTargetNotFound(String)
    case InvalidDependencyGraph(String)
    case InvalidDependencyGraphMissingTag(package: String, requestedTag: String, existingTags: String)

    case InvalidSourcesLayout(path: String, type: InvalidSourcesLayoutError)
    case UpdateRequired(String)
    
    case GitCloneFailure(String, String)
    case GitVersionTagRequired(String)

    case ManifestModuleNotFound(String)

    case NoGitRepository(String)
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
        case InvalidDependencyGraphMissingTag(let package, let requestedTag, let existingTags):
            return "The dependency graph could not be satisfied. The package (\(package)) with version tag in range (\(requestedTag)) is not found. Found tags (\(existingTags))"
        case InvalidSourcesLayout(let path, let errorType):
            return "Your source structure is not supported due to invalid sources layout: \(path). \(errorType)"
        case UpdateRequired(let package):
            return "The dependency graph could not be satisfied because an update to `\(package)' is required"
        case .GitCloneFailure(let url, let dstdir):
            return "Failed to clone \(url) to \(dstdir)"
        case .GitVersionTagRequired(let package):
            return "No version tag found in (\(package)) package. Add a version tag with \"git tag\" command. Example: \"git tag 0.1.0\""

        case .ManifestModuleNotFound(let name):
            return "Your `Package.swift' specifies a module, \(name), that does not exist on the filesystem"


        case .NoGitRepository(let name):
            return "The Package does not have a git repository: \(name)"
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