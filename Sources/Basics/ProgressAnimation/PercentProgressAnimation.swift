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

extension ProgressAnimation {
    /// A percent-based progress animation that adapts to the provided output stream.
    @_spi(SwiftPMInternal)
    public static func percent(
        stream: WritableByteStream,
        verbose: Bool,
        header: String,
        isColorized: Bool
    ) -> any ProgressAnimationProtocol {
        Self.dynamic(
            stream: stream,
            verbose: verbose,
            ttyTerminalAnimationFactory: { RedrawingPercentProgressAnimation(
                terminal: $0,
                header: header,
                isColorized: isColorized
            ) },
            dumbTerminalAnimationFactory: { SingleLinePercentProgressAnimation(stream: stream, header: header) },
            defaultAnimationFactory: { MultiLinePercentProgressAnimation(stream: stream, header: header) }
        )
    }
}

/// A redrawing lit-like progress animation.
final class RedrawingPercentProgressAnimation: ProgressAnimationProtocol {
    private let terminal: TerminalController
    private let header: String
    private let isColorized: Bool
    private var hasDisplayedHeader = false

    init(terminal: TerminalController, header: String, isColorized: Bool) {
        self.terminal = terminal
        self.header = header
        self.isColorized = isColorized
    }

    /// Creates repeating string for count times.
    /// If count is negative, returns empty string.
    private func repeating(string: String, count: Int) -> String {
        String(repeating: string, count: max(count, 0))
    }

    func colorizeText(color: TerminalController.Color = .noColor) -> TerminalController.Color {
        if self.isColorized {
            return color
        }
        return .noColor
    }

    func update(step: Int, total: Int, text: String) {
        assert(step <= total)
        let isBold = self.isColorized

        let width = self.terminal.width

        if !self.hasDisplayedHeader {
            let spaceCount = width / 2 - self.header.utf8.count / 2
            self.terminal.write(self.repeating(string: " ", count: spaceCount))
            self.terminal.write(self.header, inColor: self.colorizeText(color: .green), bold: isBold)
            self.terminal.endLine()
            self.hasDisplayedHeader = true
        } else {
            self.terminal.moveCursor(up: 1)
        }

        self.terminal.clearLine()
        let percentage = step * 100 / total
        let paddedPercentage = percentage < 10 ? " \(percentage)" : "\(percentage)"
        let prefix = "\(paddedPercentage)% " + self.terminal
            .wrap("[", inColor: self.colorizeText(color: .green), bold: isBold)
        self.terminal.write(prefix)

        let barWidth = width - prefix.utf8.count
        let n = Int(Double(barWidth) * Double(percentage) / 100.0)

        self.terminal.write(
            self.repeating(string: "=", count: n) + self.repeating(string: "-", count: barWidth - n),
            inColor: self.colorizeText(color: .green)
        )
        self.terminal.write("]", inColor: self.colorizeText(color: .green), bold: isBold)
        self.terminal.endLine()

        self.terminal.clearLine()
        if text.utf8.count > width {
            let prefix = "…"
            self.terminal.write(prefix)
            self.terminal.write(String(text.suffix(width - prefix.utf8.count)))
        } else {
            self.terminal.write(text)
        }
    }

    func complete(success: Bool) {
        self.terminal.endLine()
        self.terminal.endLine()
    }

    func clear() {
        self.terminal.clearLine()
        self.terminal.moveCursor(up: 1)
        self.terminal.clearLine()
    }
}

/// A multi-line percent-based progress animation.
final class MultiLinePercentProgressAnimation: ProgressAnimationProtocol {
    private struct Info: Equatable {
        let percentage: Int
        let text: String
    }

    private let stream: WritableByteStream
    private let header: String
    private var hasDisplayedHeader = false
    private var lastDisplayedText: String? = nil

    init(stream: WritableByteStream, header: String) {
        self.stream = stream
        self.header = header
    }

    func update(step: Int, total: Int, text: String) {
        assert(step <= total)

        if !self.hasDisplayedHeader, !self.header.isEmpty {
            self.stream.send(self.header)
            self.stream.send("\n")
            self.stream.flush()
            self.hasDisplayedHeader = true
        }

        let percentage = step * 100 / total
        self.stream.send("\(percentage)%: ").send(text)
        self.stream.send("\n")
        self.stream.flush()
        self.lastDisplayedText = text
    }

    func complete(success: Bool) {}

    func clear() {}
}
