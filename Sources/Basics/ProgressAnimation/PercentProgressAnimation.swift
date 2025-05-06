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
        return String(repeating: string, count: max(count, 0))
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

        let width = terminal.width

        if !hasDisplayedHeader {
            let spaceCount = width / 2 - header.utf8.count / 2
            terminal.write(repeating(string: " ", count: spaceCount))
            terminal.write(header, inColor: colorizeText(color: .cyan), bold: isBold)
            terminal.endLine()
            hasDisplayedHeader = true
        } else {
            terminal.moveCursor(up: 1)
        }

        terminal.clearLine()
        let percentage = step * 100 / total
        let paddedPercentage = percentage < 10 ? " \(percentage)" : "\(percentage)"
        let prefix = "\(paddedPercentage)% " + terminal
            .wrap("[", inColor: colorizeText(color: .green), bold: isBold)
        terminal.write(prefix)

        let barWidth = width - prefix.utf8.count
        let n = Int(Double(barWidth) * Double(percentage) / 100.0)

        terminal.write(
            repeating(string: "=", count: n) + repeating(string: "-", count: barWidth - n),
            inColor: colorizeText(color: .green)
        )
        terminal.write("]", inColor: colorizeText(color: .green), bold: isBold)
        terminal.endLine()

        terminal.clearLine()
        if text.utf8.count > width {
            let prefix = "…"
            terminal.write(prefix)
            terminal.write(String(text.suffix(width - prefix.utf8.count)))
        } else {
            terminal.write(text)
        }
    }

    func complete(success: Bool) {
        terminal.endLine()
        terminal.endLine()
    }

    func clear() {
        terminal.clearLine()
        terminal.moveCursor(up: 1)
        terminal.clearLine()
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

        if !hasDisplayedHeader, !header.isEmpty {
            stream.send(header)
            stream.send("\n")
            stream.flush()
            hasDisplayedHeader = true
        }

        let percentage = step * 100 / total
        stream.send("\(percentage)%: ").send(text)
        stream.send("\n")
        stream.flush()
        lastDisplayedText = text
    }

    func complete(success: Bool) {}

    func clear() {}
}
