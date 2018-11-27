/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// A protocol to operate on terminal based progress animations.
public protocol ProgressAnimationProtocol {
    /// Update the animation with a new step.
    /// - Parameters:
    ///   - step: The index of the operation's current step.
    ///   - total: The total number of steps before the operation is complete.
    ///   - text: The description of the current step.
    func update(step: Int, total: Int, text: String)

    /// Complete the animation.
    /// - Parameters:
    ///   - success: Defines if the operation the animation represents was succesful.
    func complete(success: Bool)

    /// Clear the animation.
    func clear()
}

/// A single line ninja-like progress animation.
public final class SingleLineNinjaProgressAnimation: ProgressAnimationProtocol {
    private struct State: Hashable {
        let step: Int
        let total: Int
    }

    private let stream: OutputByteStream
    private var displayedStates: Set<State> = []

    init(stream: OutputByteStream) {
        self.stream = stream
    }

    public func update(step: Int, total: Int, text: String) {
        assert(progress <= total)

        let state = State(step: step, total: total)
        guard !displayedStates.contains(state) else { return }

        stream <<< "[\(step)/\(total)] " <<< text <<< ".. "
        stream.flush()
        displayedStates.insert(state)
    }

    public func complete(success: Bool) {
        if success {
            stream <<< "OK"
            stream.flush()
        }
    }

    public func clear() {
    }
}

/// A multi-line ninja-like progress animation.
public final class MultiLineNinjaProgressAnimation: ProgressAnimationProtocol {
    private let stream: OutputByteStream

    init(stream: OutputByteStream) {
        self.stream = stream
    }

    public func update(step: Int, total: Int, text: String) {
        assert(progress <= total)

        stream <<< "[\(step)/\(total)] " <<< text
        stream <<< "\n"
        stream.flush()
    }

    public func complete(success: Bool) {
    }

    public func clear() {
    }
}

/// A redrawing ninja-like progress animation.
public final class RedrawingNinjaProgressAnimation: ProgressAnimationProtocol {
    private let terminal: TerminalController

    init(terminal: TerminalController) {
        self.terminal = terminal
    }

    public func update(step: Int, total: Int, text: String) {
        assert(progress <= total)

        terminal.clearLine()
        terminal.write("[\(step)/\(total)] ")
        terminal.write(text)
    }

    public func complete(success: Bool) {
        terminal.endLine()
    }

    public func clear() {
        terminal.clearLine()
    }
}

/// A ninja-like progress animation that adapts to the provided output stream.
public final class NinjaProgressAnimation: DynamicProgressAnimation {
    public init(stream: OutputByteStream) {
        super.init(
            stream: stream,
            ttyTerminalAnimationFactory: { RedrawingNinjaProgressAnimation(terminal: $0) },
            dumbTerminalAnimationFactory: { SingleLineNinjaProgressAnimation(stream: stream) },
            defaultAnimationFactory: { MultiLineNinjaProgressAnimation(stream: stream) })
    }
}

/// A single line percent-based progress animation.
public final class SingleLinePercentProgressAnimation: ProgressAnimationProtocol {
    private let header: String
    private var isClear: Bool
    private var stream: OutputByteStream
    private var displayed: Set<Int> = []

    init(stream: OutputByteStream, header: String) {
        self.stream = stream
        self.header = header
        self.isClear = true
    }

    public func update(step: Int, total: Int, text: String) {
        assert(progress <= total)

        if isClear {
            stream <<< header
            stream <<< "\n"
            stream.flush()
            isClear = false
        }

        let percent = step * 100 / total
        let displayPercentage = Int(Double(percent / 10).rounded(.down)) * 10
        if percent != 100, !displayed.contains(displayPercentage) {
            stream <<< String(displayPercentage) <<< ".. "
            displayed.insert(displayPercentage)
        }
        stream.flush()
    }

    public func complete(success: Bool) {
        if success {
            stream <<< "OK"
            stream.flush()
        }
    }

    public func clear() {
    }
}

/// A multi-line percent-based progress animation.
public final class MultiLinePercentProgressAnimation: ProgressAnimationProtocol {
    private let header: String
    private var isClear: Bool
    private var stream: OutputByteStream

    init(stream: OutputByteStream, header: String) {
        self.stream = stream
        self.header = header
        self.isClear = true
    }

    public func update(step: Int, total: Int, text: String) {
        assert(progress <= total)

        if isClear {
            stream <<< header
            stream <<< "\n"
            stream.flush()
            isClear = false
        }

        let percent = step * 100 / total
        stream <<< "\(percent)%: " <<< text
        stream <<< "\n"
        stream.flush()
    }

    public func complete(success: Bool) {
    }

    public func clear() {
    }
}

/// A redrawing lit-like progress animation.
public final class RedrawingLitProgressAnimation: ProgressAnimationProtocol {
    private let term: TerminalController
    private let header: String
    private var isClear: Bool // true if haven't drawn anything yet.

    init(term: TerminalController, header: String) {
        self.term = term
        self.header = header
        self.isClear = true
    }

    /// Creates repeating string for count times.
    /// If count is negative, returns empty string.
    private func repeating(string: String, count: Int) -> String {
        return String(repeating: string, count: max(count, 0))
    }

    public func update(step: Int, total: Int, text: String) {
        assert(progress <= total)

        if isClear {
            let spaceCount = (term.width/2 - header.utf8.count/2)
            term.write(repeating(string: " ", count: spaceCount))
            term.write(header, inColor: .cyan, bold: true)
            term.endLine()
            isClear = false
        }

        term.clearLine()
        let percent = step * 100 / total
        let percentString = percent < 10 ? " \(percent)" : "\(percent)"
        let prefix = "\(percentString)% " + term.wrap("[", inColor: .green, bold: true)
        term.write(prefix)

        let barWidth = term.width - prefix.utf8.count
        let n = Int(Double(barWidth) * Double(percent)/100.0)

        term.write(repeating(string: "=", count: n) + repeating(string: "-", count: barWidth - n), inColor: .green)
        term.write("]", inColor: .green, bold: true)
        term.endLine()

        term.clearLine()
        if text.utf8.count > term.width {
            let prefix = "…"
            term.write(prefix)
            term.write(String(text.suffix(term.width - prefix.utf8.count)))
        } else {
            term.write(text)
        }

        term.moveCursor(up: 1)
    }

    public func complete(success: Bool) {
        term.endLine()
        term.endLine()
    }

    public func clear() {
        term.clearLine()
        term.moveCursor(up: 1)
        term.clearLine()
    }
}

/// A percent-based progress animation that adapts to the provided output stream.
public final class PercentProgressAnimation: DynamicProgressAnimation {
    public init(stream: OutputByteStream, header: String) {
        super.init(
            stream: stream,
            ttyTerminalAnimationFactory: { RedrawingLitProgressAnimation(term: $0, header: header) },
            dumbTerminalAnimationFactory: { SingleLinePercentProgressAnimation(stream: stream, header: header) },
            defaultAnimationFactory: { MultiLinePercentProgressAnimation(stream: stream, header: header) })
    }
}

/// A progress animation that adapts to the provided output stream.
public class DynamicProgressAnimation: ProgressAnimationProtocol {
    private let animation: ProgressAnimationProtocol

    public init(
        stream: OutputByteStream,
        ttyTerminalAnimationFactory: (TerminalController) -> ProgressAnimationProtocol,
        dumbTerminalAnimationFactory: () -> ProgressAnimationProtocol,
        defaultAnimationFactory: () -> ProgressAnimationProtocol
    ) {
        if let terminal = TerminalController(stream: stream) {
            animation = ttyTerminalAnimationFactory(terminal)
        } else if let fileStream = stream as? LocalFileOutputByteStream,
            TerminalController.terminalType(fileStream) == .dumb
        {
            animation = dumbTerminalAnimationFactory()
        } else {
            animation = defaultAnimationFactory()
        }
    }

    public func update(step: Int, total: Int, text: String) {
        animation.update(step: step, total: total, text: text)
    }

    public func complete(success: Bool) {
        animation.complete(success: success)
    }

    public func clear() {
        animation.clear()
    }
}
