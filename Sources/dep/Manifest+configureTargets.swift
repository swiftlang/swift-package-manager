/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX
import sys

extension Manifest {
    /**
      Merges the configuration of this manifest with the provided computed targets.
     */
    public func configureTargets(computedTargets: [Target]) throws -> [Target]
    {
        for target in computedTargets {
            guard let matchingManifestSpecificationTarget = package.targets.pick({ manifestTarget -> Bool in
                return target.productName == manifestTarget.name
            }) else {
                continue // no dep spec
            }

            target.dependencies = try matchingManifestSpecificationTarget.dependencies.map { manifestTarget -> Target in
                switch manifestTarget {
                case .Target(let name):
                    guard let pick = computedTargets.pick({
                        return $0.productName == name
                    }) else {
                        throw Error.ManifestTargetNotFound(name)
                    }
                    return pick
                }
            }
        }

        for target in computedTargets {
            sortDependencies(target)
        }

        return computedTargets
    }
}

/**
 For the given path compute targets using our convention-based layout rules.
*/
public func determineTargets(packageName packageName: String, prefix: String, ignore: [String] = []) throws -> [Target] {
    let srcdir = try { _ -> String in
        let viableSourceRoots = walk(prefix, recursively: false).filter { entry in
            switch entry.basename.lowercaseString {
            case "sources", "source", "src", "srcs":
                return entry.isDirectory
            default:
                return false
            }
        }
        switch viableSourceRoots.count {
        case 0:
            return prefix.normpath
        case 1:
            return viableSourceRoots[0]
        default:
            // eg. there is a `Sources' AND a `src'
            throw Error.InvalidSourcesLayout(viableSourceRoots)
        }
    }()

    precondition(srcdir.isDirectory, "Sources to build absent: \(srcdir)")

    let dirs = walk(srcdir, recursively: false).filter {
        return $0.isDirectory && shouldConsiderDirectory($0) && !ignore.contains($0)
    }

    return try { () -> [Target] in
        if dirs.count == 0 {
            // If there are no subdirectories our convention is to treat the
            // root as the source directory, this is convenient for small
            // projects that want the github page to appear as simple as the
            // project *is*. You may not have any swift files in subdirectories
            let srcs = walk(srcdir, recursively: false).filter({ isValidSourceFile($0, isRoot: true) })
            if srcs.isEmpty {
                return []
            } else {
                return [try Target(name: packageName, sources: srcs)]
            }
        } else {
            return dirs.flatMap { path in
                let srcs = walk(path, recursing: shouldConsiderDirectory).filter({ isValidSourceFile($0) })
                guard srcs.count > 0 else { return nil }
                return try? Target(name: path.basename, sources: srcs)
            }
        }
    }()
}

/**
 Depth-first topological sort of target dependencies.
*/
func sortDependencies(target: Target) -> Target {
    var visited = Set<Target>()

    func recurse(target: Target) -> [Target] {
        return target.dependencies.flatMap { dep -> [Target] in
            if visited.contains(dep) {
                return []
            } else {
                visited.insert(dep)
                return recurse(dep) + [dep]
            }
        }
    }

    target.dependencies = recurse(target).reverse()
    return target
}

extension Target {
    private convenience init(name: String, sources srcs: [String]) throws {
        let islib = srcs.filter{ $0.isFile && $0.basename == "main.swift" }.isEmpty
        let type = islib ? TargetType.Library : .Executable
        try self.init(productName: name, sources: srcs, type: type)
    }
}

extension Target: Hashable {
    public var hashValue: Int { return productName.hashValue }
}

public func ==(lhs: Target, rhs: Target) -> Bool {
    return lhs.productName == rhs.productName
}

/**
 - Returns: true if the given directory should be searched for source files.
 */
private func shouldConsiderDirectory(subdir: String) -> Bool {
    let subdir = subdir.basename.lowercaseString
    if subdir == "tests" { return false }
    if subdir.hasSuffix(".xcodeproj") { return false }
    if subdir.hasSuffix(".playground") { return false }
    if subdir.hasPrefix(".") { return false }  // eg .git
    return true
}

extension Array {
    private func pick(body: (Element) -> Bool) -> Element? {
        for x in self {
            if body(x) { return x }
        }
        return nil
    }
}

/**
 Check if a given name is a candidate for a project source file.

 - Parameter isRoot: Whether we are checking on behalf of the package source root directory.
 */
private func isValidSourceFile(filename: String, isRoot: Bool = false) -> Bool {
    let base = filename.basename
    
    // If this is the root directory, reject the manifest file
    if isRoot && base.lowercaseString == Manifest.filename.lowercaseString {
        return false
    }
    
    return !base.hasPrefix(".") && filename.lowercaseString.hasSuffix(".swift")
}
