/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

struct Command {
    let node: String
    let tool: ToolProtocol

    static func createDirectory(path: String) -> Command {
        return Command(node: path, tool: MkdirTool(path: path))
    }
}
