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

import Foundation

extension FormatStyle where Self == Duration.UnitsFormatStyle {
    static var blast: Self {
        .units(
            allowed: [.hours, .minutes, .seconds, .milliseconds],
            width: .narrow,
            maximumUnitCount: 2,
            fractionalPart: .init(lengthLimits: 0...2))
    }
}

class BlastProgressAnimation {
    // Dependencies
    var terminal: TerminalController

    // Configuration
    var interactive: Bool
    var verbose: Bool
    var header: String?

    // Internal state
    var mostRecentTask: String
    var drawnLines: Int
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
        self.interactive = interactive
        self.verbose = verbose
        self.header = header
        self.mostRecentTask = ""
        self.drawnLines = 0
        self.state = .init()
    }
}

extension BlastProgressAnimation: ProgressAnimationProtocol {
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
        guard let (task, state) = update else { return }

        if self.interactive {
            self._clear()
        }

        if self.verbose, case .completed(let duration) = state {
            self._draw(task: task, duration: duration)
            self.terminal.newLine()
        }

        if self.interactive {
            self._draw()
        } else if case .started = state {
            // For the non-interactive case, only re-draw the status bar when a
            // new task starts
            self._drawStates()
            self.terminal.write(" ")
            self.terminal.write(task.name)
            self.terminal.newLine()
        }

        self._flush()
    }

    func interleave(_ bytes: some Collection<UInt8>) {
        if self.interactive { 
            self._clear()
        }
        self.terminal.write(bytes)
        if self.interactive { 
            self._draw()
        }
        self._flush()
    }

    func complete(_ message: String?) {
        self._complete(message)
        self._flush()
    }
}

extension BlastProgressAnimation {
    func _draw(state: ProgressTaskState) {
        self.terminal.text(styles: .foregroundColor(state.visualColor), .bold)
        self.terminal.write(state.visualSymbol)
    }

    func _draw(task: ProgressTask, duration: ContinuousClock.Duration?) {
        self.terminal.write(" ")
        self._draw(state: task.state)
        self.terminal.text(styles: .reset)
        self.terminal.write(" ")
        self.terminal.write(task.name)
        if let duration {
            self.terminal.text(styles: .foregroundColor(.white), .bold)
            self.terminal.write(" (\(duration.formatted(.blast)))")
            self.terminal.text(styles: .reset)
        }
    }

    func _draw(state: ProgressTaskState, count: Int, last: Bool) {
        self.terminal.text(styles: .notItalicNorBold, .foregroundColor(state.visualColor))
        self.terminal.write(state.visualSymbol)
        self.terminal.write(" \(count)")
        self.terminal.text(styles: .defaultForegroundColor, .bold)
        if !last {
            self.terminal.write(", ")
        }
    }

    func _drawStates() {
        self.terminal.text(styles: .bold)
        self.terminal.write("(")
        self._draw(state: .discovered, count: self.state.counts.pending, last: false)
        self._draw(state: .started, count: self.state.counts.running, last: false)
        self._draw(state: .completed(.succeeded), count: self.state.counts.succeeded, last: false)
        self._draw(state: .completed(.failed), count: self.state.counts.failed, last: false)
        self._draw(state: .completed(.cancelled), count: self.state.counts.cancelled, last: false)
        self._draw(state: .completed(.skipped), count: self.state.counts.skipped, last: true)
        self.terminal.write(")")
        self.terminal.text(styles: .reset)
    }

    func _drawMessage(_ message: String?) {
        if let message {
            self.terminal.write(" ")
            self.terminal.write(message)
        }
    }

    func _draw() {
        assert(self.drawnLines == 0)
        self._drawStates()
        self._drawMessage(self.header)
        self.drawnLines += 1
        let tasks = self.state.tasks.values.filter { $0.state == .started }.sorted()
        for task in tasks {
            self.terminal.newLine()
            self._draw(task: task, duration: nil)
            self.drawnLines += 1
        }
    }

    func _complete(_ message: String?) {
        self._clear()
        self._drawStates()
        self._drawMessage(message ?? self.header)
        self.terminal.newLine()
    }

    func _clear() {
        guard self.drawnLines > 0 else { return }
        self.terminal.eraseLine(.entire)
        self.terminal.carriageReturn()
        for _ in 1..<self.drawnLines {
            self.terminal.moveCursorPrevious(lines: 1)
            self.terminal.eraseLine(.entire)
        }
        self.drawnLines = 0
    }

    func _flush() {
        self.terminal.flush()
    }
}
