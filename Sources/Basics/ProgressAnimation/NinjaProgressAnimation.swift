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
        verbose: Bool,
        normalizeStep: Bool = true
    ) -> any ProgressAnimationProtocol {
        Self.dynamic(
            stream: stream,
            verbose: verbose,
            ttyTerminalAnimationFactory: { RedrawingNinjaProgressAnimation(terminal: $0, normalizeStep: normalizeStep) },
            dumbTerminalAnimationFactory: { SingleLinePercentProgressAnimation(stream: stream, header: nil) },
            defaultAnimationFactory: { MultiLineNinjaProgressAnimation(stream: stream, normalizeStep: normalizeStep) }
        )
    }
}

/// A redrawing ninja-like progress animation.
final class RedrawingNinjaProgressAnimation: ProgressAnimationProtocol {
    private let terminal: TerminalController
    private var hasDisplayedProgress = false
    private let normalizeStep: Bool

    init(terminal: TerminalController, normalizeStep: Bool) {
        self.terminal = terminal
        self.normalizeStep = normalizeStep
    }

    func update(step: Int, total: Int, text: String) {
        assert(step <= total)

        terminal.clearLine()
        var progressText = ""
        if step < 0 && normalizeStep {
            let normalizedStep = max(0, step)
            progressText = "[\(normalizedStep)/\(total)] \(text)"
        } else {
            progressText = "\(text)"
        }
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
    private let normalizeStep: Bool

    init(stream: WritableByteStream, normalizeStep: Bool) {
        self.stream = stream
        self.normalizeStep = normalizeStep
    }

    func update(step: Int, total: Int, text: String) {
        assert(step <= total)

        guard text != lastDisplayedText else { return }

        if step < 0 && normalizeStep {
            let normalizedStep = max(0, step)
            stream.send("[\(normalizedStep)/\(total)] ")
        }

        stream.send(text)
        stream.send("\n")
        stream.flush()
        lastDisplayedText = text
    }

    func complete(success: Bool) {
    }

    func clear() {
    }
}
