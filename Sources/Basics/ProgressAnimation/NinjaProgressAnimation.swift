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
    /// A ninja-like progress animation that adapts to the provided output stream.
    @_spi(SwiftPMInternal)
    public static func ninja(
        stream: WritableByteStream,
        verbose: Bool
    ) -> any ProgressAnimationProtocol {
        Self.dynamic(
            stream: stream,
            verbose: verbose,
            ttyTerminalAnimationFactory: { RedrawingNinjaProgressAnimation(terminal: $0) },
            dumbTerminalAnimationFactory: { SingleLinePercentProgressAnimation(stream: stream, header: nil) },
            defaultAnimationFactory: { MultiLineNinjaProgressAnimation(stream: stream) }
        )
    }
}

/// A redrawing ninja-like progress animation.
final class RedrawingNinjaProgressAnimation: ProgressAnimationProtocol {
    private let terminal: TerminalController
    private var hasDisplayedProgress = false

    init(terminal: TerminalController) {
        self.terminal = terminal
    }

    func update(step: Int, total: Int, text: String) {
        assert(step <= total)

        terminal.clearLine()

        let progressText = "[\(step)/\(total)] \(text)"
        let width = terminal.width
        if progressText.utf8.count > width {
            let suffix = "…"
            terminal.write(String(progressText.prefix(width - suffix.utf8.count)))
            terminal.write(suffix)
        } else {
            terminal.write(progressText)
        }

        hasDisplayedProgress = true
    }

    func complete(success: Bool) {
        if hasDisplayedProgress {
            terminal.endLine()
        }
    }

    func clear() {
        terminal.clearLine()
    }
}

/// A multi-line ninja-like progress animation.
final class MultiLineNinjaProgressAnimation: ProgressAnimationProtocol {
    private struct Info: Equatable {
        let step: Int
        let total: Int
        let text: String
    }

    private let stream: WritableByteStream
    private var lastDisplayedText: String? = nil

    init(stream: WritableByteStream) {
        self.stream = stream
    }

    func update(step: Int, total: Int, text: String) {
        assert(step <= total)

        guard text != lastDisplayedText else { return }

        stream.send("[\(step)/\(total)] ").send(text)
        stream.send("\n")
        stream.flush()
        lastDisplayedText = text
    }

    func complete(success: Bool) {
    }

    func clear() {
    }
}
