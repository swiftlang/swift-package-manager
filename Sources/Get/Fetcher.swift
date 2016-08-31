/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility

/**
 Testable protocol to recursively fetch versioned resources.
 Our usage fetches remote packages by having Sandbox conform.
 */
protocol Fetcher {
    associatedtype T: Fetchable

    func find(url: String) throws -> Fetchable?
    func fetch(url: String) throws -> Fetchable
    func finalize(_ fetchable: Fetchable) throws -> T

    func recursivelyFetch(_ urls: [(String, Range<Version>)]) throws -> [T]
}

extension Fetcher {
    /**
     Recursively fetch remote, versioned resources.
     
     This is our standard implementation that we override when testing.
     */
    func recursivelyFetch(_ urls: [(String, Range<Version>)]) throws -> [T] {

        var graph = [String: (Fetchable, Range<Version>)]()

        func recurse(_ urls: [(String, Range<Version>)]) throws -> [String] {

            return try urls.flatMap { url, specifiedVersionRange -> [String] in

                func adjust(_ pkg: Fetchable, _ versionRange: Range<Version>) throws {
                    guard let v = pkg.constrain(to: versionRange) else {
                        throw Error.invalidDependencyGraphMissingTag(package: url, requestedTag: "\(versionRange)", existingTags: "\(pkg.availableVersions)")
                    }
                    try pkg.setCurrentVersion(v)
                }

                if let (pkg, cumulativeVersionRange) = graph[url] {

                    // this package has already been checked out this instantiation
                    // verify that it satisfies the requested version range

                    guard let updatedRange = cumulativeVersionRange.constrain(to: specifiedVersionRange) else {
                        throw Error.invalidDependencyGraph(url)
                    }

                    if updatedRange ~= pkg.currentVersion {

                        // the current checked-out version is within the requested range

                        graph[url] = (pkg, updatedRange)
                        return []

                    } else {

                        // we cloned this package this instantiation, let’s attempt to
                        // modify its checkout

                        try adjust(pkg, updatedRange)
                        graph[url] = (pkg, updatedRange)

                        //FIXME we need to rewind and re-read this manifest and start again from there
                        return []
                    }

                } else if let pkg = try self.find(url: url) {

                    // this package was already installed from a previous instantiation
                    // of the package manager. Verify it is within the required version
                    // range.

                    guard specifiedVersionRange ~= pkg.currentVersion else {
                        throw Error.updateRequired(url)
                    }
                    graph[url] = (pkg, specifiedVersionRange)
                    return try recurse(pkg.children) + [url]

                } else {

                    // clone the package

                    let clone = try self.fetch(url: url)
                    try adjust(clone, specifiedVersionRange)
                    graph[url] = (clone, specifiedVersionRange)
                    return try recurse(clone.children) + [url]
                }
            }
        }
        
        return try recurse(urls).map{ graph[$0]!.0 }.map{ try self.finalize($0) }
    }
}
