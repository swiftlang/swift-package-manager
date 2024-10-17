//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public struct ProgressAnimationConfiguration {
    var style: ProgressAnimationStyle?
    var coloring: TerminalColoring?
    var interactive: Bool?

    package init(
        style: ProgressAnimationStyle? = nil,
        coloring: TerminalColoring? = nil,
        interactive: Bool? = nil
    ) {
        self.style = style
        self.coloring = coloring
        self.interactive = interactive
    }
}
