/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo

import Basic
import Utility

import func POSIX.realpath
import enum POSIX.Error

extension Git {
    class func clone(_ url: String, to dstdir: AbsolutePath) throws -> Repo {
        // Canonicalize URL.
        //
        // FIXME: This is redundant with the same code in the manifest loader.
        var url = url
        if URL.scheme(url) == nil {
            url = try realpath(url)
        }

        do {
            let env = ProcessInfo.processInfo.environment
            try system(Git.tool, "clone",
                       "--recursive",   // get submodules too so that developers can use these if they so choose
                "--depth", "10",
                url, dstdir.asString, environment: env, message: "Cloning \(url)")
        } catch POSIX.Error.exitStatus {
            // Git 2.0 or higher is required
            if let majorVersion = Git.majorVersionNumber, majorVersion < 2 {
                throw Utility.Error.obsoleteGitVersion
            } else {
                throw Error.gitCloneFailure(url, dstdir.asString)
            }
        }

        return Repo(path: dstdir)!  //TODO no bangs
    }
}
