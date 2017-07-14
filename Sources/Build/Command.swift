/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// A command represents an atomic unit of build system work.
struct Command {
    /// A unique name for the command.  This need not match any of the outputs
    /// of the tool, but it does define the stable identifier that is used to
    /// match up incremental build records.
    let name: String

    /// A configured tool instance for the command.
    /// FIXME: Clean up the names here; tool, command, task, etc.
    let tool: ToolProtocol
}

/// A target is a grouping of commands that should be built together for a
/// particular purpose.
struct Target {
    /// A unique name for the target.  These should be names that have meaning
    /// to a client wanting to control the build.
    let name: String

    /// A list of outputs that represent the target.
    var outputs: [String]

    /// A list of commands the target requires. A command may be
    /// in multiple targets, or might not be in any target at all.
    var cmds: SortedArray<Command>

    init(name: String) {
        self.name = name
        self.outputs = []
        self.cmds = SortedArray<Command>(areInIncreasingOrder: <)
    }
}

extension Command {
    static func < (lhs: Command, rhs: Command) -> Bool {
        return lhs.name < rhs.name
    }
}
