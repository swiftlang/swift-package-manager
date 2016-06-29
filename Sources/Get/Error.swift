/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version

enum Error: ErrorProtocol {

    typealias ClonePath = String
    typealias URL = String

    case gitCloneFailure(URL, ClonePath)
    case invalidDependencyGraph(ClonePath)
    case noManifest(ClonePath, Version)
    case updateRequired(ClonePath)
    case unversioned(ClonePath)
    case invalidDependencyGraphMissingTag(package: String, requestedTag: String, existingTags: String)
}

extension Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidDependencyGraph(let package):
            return "The dependency graph could not be satisfied (\(package))"
        case .invalidDependencyGraphMissingTag(let package, let requestedTag, let existingTags):
            return "The dependency graph could not be satisfied. The package (\(package)) with version tag in range (\(requestedTag)) is not found. Found tags (\(existingTags))"
        case .updateRequired(let package):
            return "The dependency graph could not be satisfied. The `\(package)' can't be updated because it has uncommitted changes. Consider committing or discarding them or deleting the Packages/ directory"
        case .gitCloneFailure(let url, let dstdir):
            return "Failed to clone \(url) to \(dstdir)"
        case .unversioned(let package):
            return "No version tag found in (\(package)) package. Add a version tag with \"git tag\" command. Example: \"git tag 0.1.0\""
        case .noManifest(let clonePath, let version):
            return "The package at `\(clonePath)' has no Package.swift for the specific version: \(version)"
        }
    }
}
