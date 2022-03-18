//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct Command {
    /// The name of the command.
    public var name: String

    /// The tool used for this command.
    public var tool: ToolProtocol

    init(name: String, tool: ToolProtocol) {
        self.name = name
        self.tool = tool
    }
}
