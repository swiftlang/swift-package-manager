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

/// A redrawing ninja-like progress animation.
final class NinjaRedrawingProgressAnimation {
    // Dependencies
    var terminal: TerminalController

    // Internal state
    var text: String
    var hasDisplayedProgress: Bool
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
        self.hasDisplayedProgress = false
        self.state = .init()
    }
}

extension NinjaRedrawingProgressAnimation: ProgressAnimationProtocol {
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
        self.text = task.name

        self._clear()
        self._draw()
        self._flush()
    }

    func interleave(_ bytes: some Collection<UInt8>) {
        self._clear()
        self.terminal.write(bytes)
        self._draw()
        self._flush()
    }

    func complete(_ message: String?) {
        self._complete(message)
        self._flush()
    }
}

extension NinjaRedrawingProgressAnimation {
    func _draw() {
        assert(!self.hasDisplayedProgress)
        let progressText = "[\(self.state.counts.completed)/\(self.state.counts.total)] \(self.text)"
        // FIXME: self.terminal.width
        let width = 80
        if progressText.utf8.count > width {
            let suffix = "…"
            self.terminal.write(String(progressText.prefix(width - suffix.utf8.count)))
            self.terminal.write(suffix)
        } else {
            self.terminal.write(progressText)
        }
        self.hasDisplayedProgress = true
    }

    func _complete(_ message: String?) {
        #warning("TODO")
        if self.hasDisplayedProgress {
            self.terminal.newLine()
        }
    }

    func _clear() {
        guard self.hasDisplayedProgress else { return }
        self.terminal.eraseLine(.entire)
        self.terminal.carriageReturn()
        self.hasDisplayedProgress = false
    }

    func _flush() {
        self.terminal.flush()
    }
}
