/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Utility

// Builds the default target in the llbuild manifest unless specified.
public func build(yamlPath: AbsolutePath, llbuild: AbsolutePath, target: String? = nil, processSet: ProcessSet) throws {
    do {
        var args = [llbuild.asString, "-f", yamlPath.asString]
        if let target = target {
            args += [target]
        }
        if verbosity != .concise { args.append("-v") }

        // Run llbuild and print output to standard streams.
        let process = Process(arguments: args, redirectOutput: false)
        try process.launch()
        try processSet.add(process)
        let result = try process.waitUntilExit() 
        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
    } catch {

        // we only check for these error conditions here
        // as it is better to let swift-build-tool figure
        // out its own error conditions and then try
        // to infer what happened afterwards.

        if isFile(yamlPath) {
            throw error
        } else {
            throw Error.buildYAMLNotFound(yamlPath.asString)
        }
    }
}
