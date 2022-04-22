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
import TSCBasic


/// Represents the result of running prebuild commands for a single plugin invocation for a target.
public struct PrebuildCommandResult {
    /// Paths of any derived files that should be included in the build.
    public var derivedFiles: [AbsolutePath]
    
    /// Paths of any directories whose contents influence the build plan.
    public var outputDirectories: [AbsolutePath]

    public init(derivedFiles: [AbsolutePath], outputDirectories: [AbsolutePath]) {
        self.derivedFiles = derivedFiles
        self.outputDirectories = outputDirectories
    }
}
