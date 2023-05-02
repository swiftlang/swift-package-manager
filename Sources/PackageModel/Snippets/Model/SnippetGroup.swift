//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

public struct SnippetGroup {
    public var name: String
    public var baseDirectory: AbsolutePath
    public var snippets: [Snippet]
    public var explanation: String

    public init(name: String, baseDirectory: AbsolutePath, snippets: [Snippet], explanation: String) {
        self.name = name
        self.baseDirectory = baseDirectory
        self.snippets = snippets
        self.explanation = explanation
        for index in self.snippets.indices {
            self.snippets[index].groupName = baseDirectory.basename
        }
    }
}
