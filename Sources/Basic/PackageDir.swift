/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Utility

public func isSafeToRemove(_ item: String) -> Bool {
    // Only look at repositories.
    guard item.appending(".git").asString.exists else { continue }

    // If there is a staged or unstaged diff, don't remove the
    // tree. This won't detect new untracked files, but it is
    // just a safety measure for now.
    let diffArgs = ["--no-ext-diff", "--quiet", "--exit-code"]
    do {
        _ = try Git.runPopen([Git.tool, "-C", item.asString, "diff"] + diffArgs)
        _ = try Git.runPopen([Git.tool, "-C", item.asString, "diff", "--cached"] + diffArgs)
    } catch {
        return false
    }
    return true
}

