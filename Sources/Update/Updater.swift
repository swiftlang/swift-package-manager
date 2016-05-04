/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -----------------------------------------------------------------

 The depedency engine, allowing update() on top to do the actual
 heavy lifting of manifest parsing, git operations and filesystem
 operations.
*/

import struct PackageDescription.Version
import struct PackageType.Manifest
import struct Utility.Path
import func POSIX.rename

public typealias URL = String


class Updater {
    private var queue = Queue()
    private var graph = [URL: Range<Version>]()
    private var parsed = Set<URL>()
    private var parsedVersionRecord = [URL: Version]()
    private var fetched = Set<URL>()

    init(dependencies: [(URL, Range<Version>)]) {
        for (url, range) in dependencies {
            queue.push(url)
            graph[url] = range
        }
    }

    /**
      Packages enter the system as URLs, they
      are then fed via calls to crank() to a manager of some sort,
      they then re-enter the system as Checkouts where they will
      later be updated as necessary. This may seem more elaborate
      than necessary, but it is the lowest level of abstraction
      considering packages may not be cloned yet (new dependencies)
      and not all inputs are packages (the rootManifest).
    */
    func crank() throws -> Turn? {
        guard let (url, state) = queue.pop() else { return nil }

        switch state {
        case .Unknown:
            queue.push(url, state: .Fetched)
            return .Fetch(url)
        case .Fetched:
            parsed.insert(url)

            func ff(fff: (Specification) throws -> ([Specification], Version)) throws {
                let (specs, manifestVersion) = try fff((url, graph[url]!))
                for (url, range) in specs { try enqueue(url: url, range: range) }
                parsedVersionRecord[url] = manifestVersion
            }

            return .ReadManifest(ff)
        case .Parsed:
            queue.set(done: url)
            return .Update(url, graph[url]!)
        case .Updated:
            fatalError("Programmer error")
        }
    }

    private func enqueue(url: URL, range: Range<Version>) throws {
        guard let cumulativeVersionRange = graph[url] else {
            // new dependency we haven't seen yet
            graph[url] = range
            return queue.push(url)
        }
        guard let constrainedVersionRange = cumulativeVersionRange.constrained(to: range) else {
            //TODO a complicated alogrithm could attempt previous versions
            // of the dependencies that cause conflict and try to find a
            // good graph. However practically the user will probably
            // find this an easier task since they can read documentation
            // and figure out why a specific dependency has clamped their
            // dependencies so stringently.
            //NOTE we should probably not bother for incompatabilities that
            // are major eg. Foo-1.x and Foo-2.x
            //NOTE maybe we shouldn't bother at all? There is probably good
            // reason the graph has failed. Maybe the user should always
            // have to invesigate, so instead we should provide good
            // diagnostics.
            throw Error.GraphCannotBeSatisfied(url)
        }
        if let versionUsedForParsing = parsedVersionRecord[url] {
            // we can fix this by undoing all the constraints imposed
            // by this package and then redoing the graph from there
            // an easy first attempt would be to just restart the whole
            // dependency graph with this additional constraint imposed
            // at the start, but this is not a performant solution obv.

            guard constrainedVersionRange ~= versionUsedForParsing else {
                throw Error.AlreadyParsedWithVersionOutOfRange(url)
            }
        }

        graph[url] = constrainedVersionRange
        queue.push(url)
    }

    enum Turn {
        /**
          Fetch or clone the dependency as necessary so its version information
          is up-to-date.
        */
        case Fetch(URL)
        /**
          Call the provided function, parse the manifest and return its deps
          and the version of the package that had the manifest.
        */
        case ReadManifest(((Specification) throws -> ([Specification], Version)) throws -> Void)

        /**
          Update the package within the provided range if neccessary.
        */
        case Update(URL, Range<Version>)
    }
}

typealias Specification = (url: URL, versionRange: Range<Version>)

public enum Error: ErrorProtocol {
    case GraphCannotBeSatisfied(URL)
    case AlreadyParsedWithVersionOutOfRange(URL)
}
