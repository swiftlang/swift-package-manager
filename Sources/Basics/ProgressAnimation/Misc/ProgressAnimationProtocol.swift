//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import protocol TSCBasic.WritableByteStream

// TODO: This protocol could be extended to handle a task tree
package protocol ProgressAnimationProtocol {
    init(
        stream: any WritableByteStream,
        coloring: TerminalColoring,
        interactive: Bool,
        verbose: Bool,
        header: String?)

    func update(
        id: Int,
        name: String,
        event: ProgressTaskState,
        at time: ContinuousClock.Instant)

    /// Interleave some other output with the progress animation.
    func interleave(_ bytes: some Collection<UInt8>)

    /// Complete the animation.
    func complete(_ message: String?)
}

extension ProgressAnimationProtocol {
    /// Interleave some other output with the progress animation.
    package func interleave(_ text: String) {
        self.interleave(text.utf8)
    }
}