/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version

public enum Error: ErrorProtocol {

    public typealias ClonePath = String
    public typealias URL = String

    case GitCloneFailure(URL, ClonePath)
    case InvalidDependencyGraph(ClonePath)
    case NoManifest(ClonePath, Version)
    case UpdateRequired(ClonePath)
    case Unversioned(ClonePath)
    case InvalidDependencyGraphMissingTag(package: String, requestedTag: String, existingTags: String)
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case InvalidDependencyGraph(let package):
            return "The dependency graph could not be satisfied (\(package))"
        case InvalidDependencyGraphMissingTag(let package, let requestedTag, let existingTags):
            return "The dependency graph could not be satisfied. The package (\(package)) with version tag in range (\(requestedTag)) is not found. Found tags (\(existingTags))"
        case UpdateRequired(let package):
            return "The dependency graph could not be satisfied because an update to `\(package)' is required"
        case .GitCloneFailure(let url, let dstdir):
            return "Failed to clone \(url) to \(dstdir)"
        case .Unversioned(let package):
            return "No version tag found in (\(package)) package. Add a version tag with \"git tag\" command. Example: \"git tag 0.1.0\""
        case NoManifest(let clonePath, let version):
            return "The package at `\(clonePath)' has no Package.swift for the specific version: \(version)"
        }
    }
}
