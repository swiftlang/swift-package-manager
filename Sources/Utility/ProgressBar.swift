/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Dispatch

/// A protocol to operate on terminal based progress bars.
public protocol ProgressBarProtocol {
    func update(percent: Int, text: String)
    func complete(success: Bool)
}

/// A single line progress bar.
public final class SingleLineProgressBar: ProgressBarProtocol {
    private let header: String
    private var isClear: Bool
    private var stream: OutputByteStream
    private var displayed: Set<Int> = []

    init(stream: OutputByteStream, header: String) {
        self.stream = stream
        self.header = header
        self.isClear = true
    }

    public func update(percent: Int, text: String) {
        if isClear {
            stream <<< header
            stream <<< "\n"
            stream.flush()
            isClear = false
        }

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
}

/// Simple ProgressBar which shows the update text in new lines.
public final class SimpleProgressBar: ProgressBarProtocol {
    private let header: String
    private var isClear: Bool
    private var stream: OutputByteStream

    init(stream: OutputByteStream, header: String) {
        self.stream = stream
        self.header = header
        self.isClear = true
    }

    public func update(percent: Int, text: String) {
        if isClear {
            stream <<< header
            stream <<< "\n"
            stream.flush()
            isClear = false
        }

        stream <<< "\(percent)%: " <<< text
        stream <<< "\n"
        stream.flush()
    }

    public func complete(success: Bool) {
    }
}

/// Three line progress bar with header, redraws on each update.
public final class ProgressBar: ProgressBarProtocol {
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

    public func update(percent: Int, text: String) {
        if isClear {
            let spaceCount = (term.width/2 - header.utf8.count/2)
            term.write(repeating(string: " ", count: spaceCount))
            term.write(header, inColor: .cyan, bold: true)
            term.endLine()
            isClear = false
        }

        term.clearLine()
        let percentString = percent < 10 ? " \(percent)" : "\(percent)"
        let prefix = "\(percentString)% " + term.wrap("[", inColor: .green, bold: true)
        term.write(prefix)

        let barWidth = term.width - prefix.utf8.count
        let n = Int(Double(barWidth) * Double(percent)/100.0)

        term.write(repeating(string: "=", count: n) + repeating(string: "-", count: barWidth - n), inColor: .green)
        term.write("]", inColor: .green, bold: true)
        term.endLine()

        term.clearLine()
        term.write(text)

        term.moveCursor(up: 1)
    }

    public func complete(success: Bool) {
        term.endLine()
    }
}

/// Creates colored or simple progress bar based on the provided output stream.
public func createProgressBar(forStream stream: OutputByteStream, header: String) -> ProgressBarProtocol {
    guard let stdStream = stream as? LocalFileOutputByteStream else {
        return SimpleProgressBar(stream: stream, header: header)
    }

    // If we have a terminal, use animated progress bar.
    if let term = TerminalController(stream: stdStream) {
        return ProgressBar(term: term, header: header)
    }

    // If the terminal is dumb, use single line progress bar.
    if TerminalController.terminalType(stdStream) == .dumb {
        return SingleLineProgressBar(stream: stream, header: header)
    }

    // Use simple progress bar by default.
    return SimpleProgressBar(stream: stream, header: header)
}

// MARK: - LaneBasedProgressBar

public protocol LaneBasedProgressBarLaneProtocol: class {
    func update(text: String)
    func complete()
}

public protocol LaneBasedProgressBarProtocol {
    func createLane(name: String) -> LaneBasedProgressBarLaneProtocol
    func complete(text: String)
}

public func createLaneBasedProgressBar(
    forStream stream: OutputByteStream,
    numLanes: Int
) -> LaneBasedProgressBarProtocol {
    guard let stdStream = stream as? LocalFileOutputByteStream else {
        return SimpleLaneBasedProgressBar(forStream: stream, numLanes: numLanes)
    }
    if TerminalController.terminalType(stdStream) == .tty {
        if let term = TerminalController(stream: stdStream) {
            return LaneBasedProgressBar(term: term, numLanes: numLanes)
        }
    }
    return SimpleLaneBasedProgressBar(forStream: stream, numLanes: numLanes)
}

public final class SimpleLaneBasedProgressBar: LaneBasedProgressBarProtocol {

    public final class Lane: LaneBasedProgressBarLaneProtocol, ObjectIdentifierProtocol {

        let name: String
        private unowned let progressBar: SimpleLaneBasedProgressBar

        var queue: DispatchQueue {
            return progressBar.queue
        }

        var stream: OutputByteStream {
            return progressBar.stream
        }

        init(name: String, progressBar: SimpleLaneBasedProgressBar) {
            self.name = name
            self.progressBar = progressBar
        }

        public func update(text: String) {
            queue.sync {
                stream <<< name <<< ": " <<< text <<< "\n"
                stream.flush()
            }
        }

        public func complete() {
            queue.sync {
                stream <<< name <<< ": Done" <<< "\n"
                stream.flush()
            }
        }
    }

    private let queue = DispatchQueue(label: "org.swift.swiftpm.something-2")

    let stream: OutputByteStream

    public init(forStream stream: OutputByteStream, numLanes: Int) {
        self.stream = stream
    }

    public func createLane(name: String) -> LaneBasedProgressBarLaneProtocol {
        return Lane(name: name, progressBar: self)
    }

    public func complete(text: String) {
        queue.sync {
            stream <<< text <<< "\n"
            stream.flush()
        }
    }
}

public final class LaneBasedProgressBar: LaneBasedProgressBarProtocol {

    public final class Lane: LaneBasedProgressBarLaneProtocol, ObjectIdentifierProtocol {

        fileprivate var name: String
        fileprivate var text: String
        fileprivate var isIdle: Bool

        private unowned let progressBar: LaneBasedProgressBar

        fileprivate init(progressBar: LaneBasedProgressBar) {
            self.progressBar = progressBar
            self.name = ""
            self.text = ""
            self.isIdle = true
            reset()
        }

        private func reset() {
            self.name = "Idle"
            self.text = ""
            self.isIdle = true
        }

        public func update(text: String) {
            progressBar.queue.sync {
                self.text = text
            }
            progressBar.redraw()
        }

        public func complete() {
            progressBar.queue.sync {
                self.reset()
            }
            progressBar.redraw()
        }
    }

    private let term: TerminalController

    private var lanes: [Lane]

    private var isClear = true

    private let queue = DispatchQueue(label: "org.swift.swiftpm.something-2")

    public init(term: TerminalController, numLanes: Int) {
        self.term = term
        self.lanes = []
        self.lanes = (0..<numLanes).map({ _ -> Lane in
            Lane(progressBar: self)
        })
    }

    public func createLane(name: String) -> LaneBasedProgressBarLaneProtocol {
        return queue.sync {
            let lane = lanes.first(where: { $0.isIdle })!
            lane.isIdle = false
            lane.name = name
            return lane
        }
    }

    private func redraw() {
        queue.async {
            if self.isClear {
                self.isClear = false
            } else {
                self.clear()
            }

            for lane in self.lanes {
                self.term.write("├── ")

                if lane.isIdle {
                    self.term.write(lane.name, inColor: .noColor)
                } else {
                    self.term.write(lane.name, inColor: .black, bold: true)
                }
                if !lane.text.isEmpty {
                    self.term.write(": " + lane.text)
                }
                self.term.endLine()
            }
        }
    }

    private func clear() {
        for _ in lanes {
            term.moveCursor(up: 1)
            term.clearLine()
        }
    }

    public func complete(text: String) {
        queue.sync {
            clear()
            self.term.write(text)
            self.term.endLine()
        }
    }
}
