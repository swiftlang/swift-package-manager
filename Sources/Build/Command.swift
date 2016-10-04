/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

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
