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

import func libc.fflush
import var libc.stdout
import Update

func update(root: String) throws {
    guard root.isDirectory else { throw Error.FetchRequired }

    let delta: Delta
    do {
        defer { print("") }

        delta = try update(root: root) { status in
            switch status {
            case .Start(let count):
                print("Updating \(count) packages")
            case .Fetching:
                print(".", terminator: "")
            }
            fflush(libc.stdout)
        }
    }

    print(delta)
}

extension Delta: CustomStringConvertible {
    public var description: String {
        if added.isEmpty && removed.isEmpty && upgraded.isEmpty && downgraded.isEmpty && !unchanged.isEmpty {
            return "notice: no versions changed"
        }

        var lines = [String]()
        for (name, v1, v2) in upgraded {
            lines.append("⬆ \(name) \(v1) → \(v2)")
        }
        for (name, v1) in unchanged {
            lines.append("= \(name) \(v1)")
        }
        return lines.joined(separator: "\n")
    }
}
