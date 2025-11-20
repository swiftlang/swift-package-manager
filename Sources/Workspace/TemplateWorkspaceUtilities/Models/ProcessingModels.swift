//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct TemplateCommandPath {
    public let fullPathKey: String
    public let commandChain: [CommandComponent]

    public init(fullPathKey: String, commandChain: [CommandComponent]) {
        self.fullPathKey = fullPathKey
        self.commandChain = commandChain
    }
}

public struct CommandComponent {
    public let commandName: String
    public let arguments: [ArgumentResponse]

    public init(commandName: String, arguments: [ArgumentResponse]) {
        self.commandName = commandName
        self.arguments = arguments
    }
}
