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

/// A single line percent-based progress animation.
final class PercentSingleLineProgressAnimation {
    // Dependencies
    var terminal: TerminalController

    // Configuration
    let header: String?

    // Internal state
    var displayedPercentages: Set<Int>
    var hasDisplayedHeader: Bool
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
        self.displayedPercentages = []
        self.hasDisplayedHeader = false
        self.state = .init()
    }
}

extension PercentSingleLineProgressAnimation: ProgressAnimationProtocol {
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
        guard update != nil else { return }

        if let header = self.header, !self.hasDisplayedHeader {
            self.terminal.write(header)
            self.terminal.newLine()
            self.terminal.flush()
            self.hasDisplayedHeader = true
        }

        let percentage = self.state.counts.percentage
        let roundedPercentage = Int(Double(percentage / 10).rounded(.down)) * 10
        if percentage < 100, 
            self.displayedPercentages.insert(roundedPercentage).inserted
        {
            self.terminal.write("\(roundedPercentage).. ")
        }
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
