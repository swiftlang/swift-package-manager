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

import class TSCBasic.TerminalController
import class TSCBasic.LocalFileOutputByteStream
import protocol TSCBasic.WritableByteStream
import protocol TSCUtility.ProgressAnimationProtocol

@_spi(SwiftPMInternal_ProgressAnimation)
public typealias ProgressAnimationProtocol = TSCUtility.ProgressAnimationProtocol

/// Namespace to nest public progress animations under.
@_spi(SwiftPMInternal_ProgressAnimation)
public enum ProgressAnimation {
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

