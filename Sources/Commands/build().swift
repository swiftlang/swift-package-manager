/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

// Builds the default target in the llbuild manifest unless specified.
public func build(yamlPath: AbsolutePath, target: String? = nil) throws {
    do {
        var args = [ToolDefaults.llbuild.asString, "-f", yamlPath.asString]
        if let target = target {
            args += [target]
        }
        if verbosity != .concise { args.append("-v") }
        try system(args)
    } catch {

        // we only check for these error conditions here
        // as it is better to let swift-build-tool figure
        // out its own error conditions and then try
        // to infer what happened afterwards.

        if try isFile(yamlPath) {
            throw error
        } else {
            throw Error.buildYAMLNotFound(yamlPath.asString)
        }
    }
}
