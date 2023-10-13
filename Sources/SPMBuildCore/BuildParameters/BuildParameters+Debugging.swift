//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.Triple

extension BuildParameters {
    public struct Debugging: Encodable {
        public init(
            debugInfoFormat: DebugInfoFormat = .dwarf,
            targetTriple: Triple,
            shouldEnableDebuggingEntitlement: Bool
        ) {
            self.debugInfoFormat = debugInfoFormat

            // Per rdar://112065568 for backtraces to work on macOS a special entitlement needs to be granted on the final
            // executable.
            self.shouldEnableDebuggingEntitlement = targetTriple.isMacOSX && shouldEnableDebuggingEntitlement
        }

        public var debugInfoFormat: DebugInfoFormat
        
        /// Whether the produced executable
        public var shouldEnableDebuggingEntitlement: Bool
    }

    /// Represents the debugging strategy.
    ///
    /// Swift binaries requires the swiftmodule files in order for lldb to work.
    /// On Darwin, linker can directly take the swiftmodule file path using the
    /// -add_ast_path flag. On other platforms, we convert the swiftmodule into
    /// an object file using Swift's modulewrap tool.
    public enum DebuggingStrategy {
        case swiftAST
        case modulewrap
    }

    /// The debugging strategy according to the current build parameters.
    public var debuggingStrategy: DebuggingStrategy? {
        guard configuration == .debug else {
            return nil
        }

        if targetTriple.isApple() {
            return .swiftAST
        }
        return .modulewrap
    }

    /// Represents the debug information format.
    ///
    /// The debug information format controls the format of the debug information
    /// that the compiler generates.  Some platforms support debug information
    // formats other than DWARF.
    public enum DebugInfoFormat: String, Encodable {
        /// DWARF debug information format, the default format used by Swift.
        case dwarf
        /// CodeView debug information format, used on Windows.
        case codeview
        /// No debug information to be emitted.
        case none
    }

}
