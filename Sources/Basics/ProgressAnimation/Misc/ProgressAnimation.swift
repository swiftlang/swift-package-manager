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

public typealias WritableByteStream = TSCBasic.WritableByteStream

/// Namespace for progress animations.
package enum ProgressAnimation {
    /// A lit-like progress animation that adapts to the provided output stream.
    static func lit(
        interactive: Bool,
        verbose: Bool
    ) -> ProgressAnimationProtocol.Type {
        if !interactive {
            PercentSingleLineProgressAnimation.self
        } else if !verbose {
            PercentRedrawingProgressAnimation.self
        } else {
            PercentMultiLineProgressAnimation.self
        }
    }

    /// A ninja-like progress animation that adapts to the provided output
    /// stream.
    static func ninja(
        interactive: Bool,
        verbose: Bool
    ) -> ProgressAnimationProtocol.Type {
        if interactive {
            NinjaRedrawingProgressAnimation.self
        } else {
            NinjaMultiLineProgressAnimation.self
        }
    }

    package static func make(
        configuration: ProgressAnimationConfiguration,
        environment: Environment,
        stream: WritableByteStream,
        verbose: Bool,
        header: String?
    ) -> any ProgressAnimationProtocol {
        let environmentBarStyle: ProgressAnimationStyle? =
            if environment["SWIFTPM_TEST_RUNNER_PROGRESS_BAR"] == "lit" {
                .lit
            } else {
                nil
            }
        let style =
            // User requested style
            configuration.style
            // Falling back to style set in the env
            ?? environmentBarStyle
            // Default to blast if unknown
            ?? .blast

        let capabilities = TerminalCapabilities(
            stream: stream,
            environment: environment)
        let interactive =
            // User requested interactivity
            configuration.interactive
            // Falling back to env x tty determined interactivity
            ?? capabilities.interactive
        let coloring =
            // User requested colors
            configuration.coloring
            // Falling back to env determined interactivity
            ?? capabilities.coloring
            // Default to 8 colors if unknown
            ?? ._8

        let type = switch style {
            case .blast: BlastProgressAnimation.self
            case .ninja: Self.ninja(interactive: interactive, verbose: verbose)
            case .lit: Self.lit(interactive: interactive, verbose: verbose)
            }
        return type.init(
            stream: stream,
            coloring: coloring,
            interactive: interactive,
            verbose: verbose,
            header: header)
    }
}
