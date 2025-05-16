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

import class TSCBasic.TerminalController
import protocol TSCBasic.WritableByteStream

/// A redrawing lit-like progress animation.
final class PercentRedrawingProgressAnimation {
    // Dependencies
    var terminal: TerminalController

    // Configuration
    var header: String?

    // Internal state
    var text: String
    var hasDisplayedHeader: Bool
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
        self.header = header
        self.text = ""
        self.hasDisplayedHeader = false
        self.hasDisplayedProgress = false
        self.state = .init()
    }
}

extension PercentRedrawingProgressAnimation: ProgressAnimationProtocol {
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

extension PercentRedrawingProgressAnimation {
    /// Draws a progress bar with centered header above and description below.
    ///
    /// The drawn progress bar looks like the following:
    ///
    /// ```
    /// ╭──────────────────────────────────────────────╮
    /// │              Building Firmware!              │
    /// │75% [==============================----------]│
    /// │Compiling main.swift                          │
    /// ╰──────────────────────────────────────────────╯
    /// ```
    func _draw() {
        // FIXME: self.terminal.width
        let width = 80
        if let header = self.header, !self.hasDisplayedHeader {
            // Center the header above the bar
            let padding = max((width / 2) - (header.utf8.count / 2), 0)
            self.terminal.write(String(repeating: " ", count: padding))
            self.terminal.text(styles: .foregroundColor(.cyan), .bold)
            self.terminal.write(header)
            self.terminal.text(styles: .reset)
            self.terminal.newLine()
            self.hasDisplayedHeader = true
        }

        // Draw '<num>% ' prefix
        let percentage = Int(self.state.counts.percentage * 100).clamp(0...100)
        let percentageDescription = "\(percentage)"
        self.terminal.write(percentageDescription)
        self.terminal.write("% ")
        let prefixLength = 2 + percentageDescription.utf8.count

        // Draw '[===---]' bar
        self.terminal.text(styles: .foregroundColor(.green), .rapidBlink)
        self.terminal.write("[")
        let barLength = width - prefixLength - 2
        let barCompletedLength = Int(Double(barLength) * Double(self.state.counts.percentage))
        let barRemainingLength = barLength - barCompletedLength
        self.terminal.write(String(repeating: "=", count: barCompletedLength))
        self.terminal.write(String(repeating: "-", count: barRemainingLength))
        self.terminal.write("]")
        self.terminal.text(styles: .reset)
        self.terminal.newLine()

        // Draw task name
        if self.text.utf8.count > width {
            let prefix = "…"
            self.terminal.write(prefix)
            self.terminal.write(String(self.text.suffix(width - prefix.utf8.count)))
        } else {
            self.terminal.write(self.text)
        }
        self.hasDisplayedProgress = true
    }

    func _complete(_ message: String?) {
        self._clear()
        guard self.hasDisplayedHeader else { return }
        self.terminal.carriageReturn()
        self.terminal.moveCursorUp(cells: 1)
        self.terminal.eraseLine(.entire)
        if let message {
            self.terminal.write(message)
        }
    }

    func _clear() {
        guard self.hasDisplayedProgress else { return }
        self.terminal.eraseLine(.entire)
        self.terminal.carriageReturn()
        self.terminal.moveCursorUp(cells: 1)
        self.terminal.eraseLine(.entire)
        self.hasDisplayedProgress = false
    }

    func _flush() {
        self.terminal.flush()
    }
}

extension Comparable {
    func clamp(_ range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
