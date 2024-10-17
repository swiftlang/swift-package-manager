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

/// A multi-line ninja-like progress animation.
final class NinjaMultiLineProgressAnimation {
    // Dependencies
    var terminal: TerminalController

    // Internal state
    var text: String
    var state: ProgressState

    required init(
        stream: any WritableByteStream,
        coloring: TerminalColoring,
        interactive: Bool,
        verbose: Bool,
        header: String?
    ) {
        self.terminal = TerminalController(
            stream: stream,
            coloring: coloring)
        self.text = ""
        self.state = .init()
    }
}

extension NinjaMultiLineProgressAnimation: ProgressAnimationProtocol {
    func update(
        id: Int,
        name: String,
        event: ProgressTaskState,
        at time: ContinuousClock.Instant
    ) {
        let update = self.state.update(
            id: id,
            name: name,
            state: event,
            at: time)
        guard let (task, _) = update else { return }
        guard self.text != task.name else { return }
        self.text = task.name
        self.terminal.write(
            "[\(self.state.counts.completed)/\(self.state.counts.total)] ")
        self.terminal.write(self.text)
        self.terminal.newLine()
        self.terminal.flush()
    }

    func interleave(_ bytes: some Collection<UInt8>) {
        self.terminal.write(bytes)
        self.terminal.flush()
    }

    func complete(_ message: String?) {
        if let message {
            self.terminal.write(message)
            self.terminal.flush()
        }
    }
}
