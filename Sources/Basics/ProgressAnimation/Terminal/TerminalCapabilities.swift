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

import protocol TSCBasic.WritableByteStream

package struct TerminalCapabilities {
    var coloring: TerminalColoring?
    var interactive: Bool
}

extension TerminalCapabilities {
    init(
        stream: WritableByteStream,
        environment: Environment
    ) {
        self.coloring = Self.coloring(
            stream: stream,
            environment: environment
        )
        self.interactive = Self.interactive(
            stream: stream,
            environment: environment
        )
    }
}
