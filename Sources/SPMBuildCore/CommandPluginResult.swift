//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

@available(*,
    deprecated,
    renamed: "CommandPluginResult",
    message: "renamed to unify terminology with the Swift Evolution proposal"
)
public typealias PrebuildCommandResult = CommandPluginResult

/// Represents the result of running a command plugin for a single plugin invocation for a target.
public struct CommandPluginResult {
    /// Paths of any derived files that should be included in the build.
    public var derivedFiles: [AbsolutePath]
    
    /// Paths of any directories whose contents influence the build plan.
    public var outputDirectories: [AbsolutePath]

    public init(derivedFiles: [AbsolutePath], outputDirectories: [AbsolutePath]) {
        self.derivedFiles = derivedFiles
        self.outputDirectories = outputDirectories
    }
}
