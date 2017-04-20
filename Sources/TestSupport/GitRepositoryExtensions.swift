/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility
import SourceControl

/// Extensions useful for unit testing purposes.
/// Note: These are not thread safe.
public extension GitRepository {

    /// Create the repository using git init.
    func create() throws {
        try systemQuietly([Git.tool, "-C", path.asString, "init"])
    }

    /// Returns current branch name. If HEAD is on a detached state, this returns HEAD.
    func currentBranch() throws -> String {
        return try Process.checkNonZeroExit(
            args: Git.tool, "-C", path.asString, "rev-parse", "--abbrev-ref", "HEAD").chomp()
    }

    /// Stage a file.
    func stage(file: String) throws {
        try systemQuietly([Git.tool, "-C", path.asString, "add", file])
    }

    /// Stage multiple files.
    func stage(files: String...) throws {
        try systemQuietly([Git.tool, "-C", path.asString, "add"] + files)
    }

    /// Stage entire unstaged changes.
    func stageEverything() throws {
        try systemQuietly([Git.tool, "-C", path.asString, "add", "."])
    }

    /// Commit the staged changes. If the message is not provided a dummy message will be used for the commit.
    func commit(message: String? = nil) throws {
        // FIXME: We don't need to set these everytime but we usually only commit once or twice for a test repo.
        try systemQuietly([Git.tool, "-C", path.asString, "config", "user.email", "example@example.com"])
        try systemQuietly([Git.tool, "-C", path.asString, "config", "user.name", "Example Example"])
        try systemQuietly([Git.tool, "-C", path.asString, "config", "commit.gpgsign", "false"])
        try systemQuietly([Git.tool, "-C", path.asString, "commit", "-m", message ?? "Add some files."])
    }

    /// Tag the git repo.
    func tag(name: String) throws {
        try systemQuietly([Git.tool, "-C", path.asString, "tag", name])
    }

    /// Push the changes to specified remote and branch.
    func push(remote: String, branch: String) throws {
        try systemQuietly([Git.tool, "-C", path.asString, "push", remote, branch])
    }
}
