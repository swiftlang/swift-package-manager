/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file provides diagnostics that a user can inspect to infer common
 build troubles or for other troubleshooting purposes.
*/

import struct PackageType.Manifest
import func libc.fflush
import var Utility.verbosity
import var libc.stdout
import Update


func update(root: String, pkgdir: String) throws {
    guard root.isDirectory else { throw Error.FetchRequired }

    let manifest = try parseManifest(path: root, baseURL: root)

    let delta: Delta
    do {
        defer { print("") }

        let deps = manifest.package.dependencies.map{ ($0.url, $0.versionRange) }

        delta = try update(dependencies: deps, manifestParser: parseManifest, pkgdir: pkgdir) { status in
            switch (verbosity, status) {
            case (_, .Start(let count)):
                print("Updating \(count) packages")
            case (.Concise, _):
                print(".", terminator: "")
                fflush(libc.stdout)
            default:
                print(status)
            }
        }
    }

    print(delta)
}


//MARK: helpers

extension Delta: CustomStringConvertible {
    public var description: String {
        if added.isEmpty && changed.isEmpty {
            return "notice: no change"
        }

        var lines = [String]()
        for (name, v1, v2) in changed {
            if v2 > v1 {
                lines.append("⬆ \(name) \(v1) → \(v2)")
            } else {
                lines.append("⬇ \(name) \(v1) → \(v2)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
