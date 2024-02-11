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
import class TSCBasic.LocalFileOutputByteStream
import protocol TSCBasic.WritableByteStream
import protocol TSCUtility.ProgressAnimationProtocol

@_spi(SwiftPMInternal)
public typealias ProgressAnimationProtocol = TSCUtility.ProgressAnimationProtocol

/// Namespace to nest public progress animations under.
@_spi(SwiftPMInternal)
public enum ProgressAnimation {
    /// Dynamically create a progress animation based on the current stream
    /// capabilities and desired verbosity.
    ///
    /// - Parameters:
    ///   - stream: A stream to write animations into.
    ///   - verbose: The verbosity level of other output in the system.
    ///   - ttyTerminalAnimationFactory: A progress animation to use when the
    ///     output stream is connected to a terminal with support for special
    ///     escape sequences.
    ///   - dumbTerminalAnimationFactory: A progress animation to use when the
    ///     output stream is connected to a terminal without support for special
    ///     escape sequences for clearing lines or controlling cursor positions.
    ///   - defaultAnimationFactory: A progress animation to use when the
    ///     desired output is verbose or the output stream verbose or is not
    ///     connected to a terminal, e.g. a pipe or file.
    /// - Returns: A progress animation instance matching the stream
    ///   capabilities and desired verbosity.
    static func dynamic(
        stream: WritableByteStream,
        verbose: Bool,
        ttyTerminalAnimationFactory: (TerminalController) -> any ProgressAnimationProtocol,
        dumbTerminalAnimationFactory: () -> any ProgressAnimationProtocol,
        defaultAnimationFactory: () -> any ProgressAnimationProtocol
    ) -> any ProgressAnimationProtocol {
        if let terminal = TerminalController(stream: stream), !verbose {
            return ttyTerminalAnimationFactory(terminal)
        } else if let fileStream = stream as? LocalFileOutputByteStream,
                  TerminalController.terminalType(fileStream) == .dumb
        {
            return dumbTerminalAnimationFactory()
        } else {
            return defaultAnimationFactory()
        }
    }
}

