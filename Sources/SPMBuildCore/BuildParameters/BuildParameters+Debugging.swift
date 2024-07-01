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
import enum PackageModel.BuildConfiguration

extension BuildParameters {
    public struct Debugging: Encodable {
        public init(
            debugInfoFormat: DebugInfoFormat = .dwarf,
            triple: Triple,
            shouldEnableDebuggingEntitlement: Bool,
            omitFramePointers: Bool?
        ) {
            self.debugInfoFormat = debugInfoFormat

            // Per rdar://112065568 for backtraces to work on macOS a special entitlement needs to be granted on the final
            // executable.
            self.shouldEnableDebuggingEntitlement = triple.isMacOSX && shouldEnableDebuggingEntitlement
            // rdar://117578677: frame-pointer to support backtraces
            // this can be removed once the backtracer uses DWARF instead of frame pointers
            if let omitFramePointers {
                // if set, we respect user's preference
                self.omitFramePointers = omitFramePointers
            } else if triple.isLinux() {
                // on Linux we preserve frame pointers by default
                self.omitFramePointers = false
            } else {
                // otherwise, use the platform default
                self.omitFramePointers = nil
            }
        }

        public var debugInfoFormat: DebugInfoFormat
        
        /// Whether the produced executable should be codesigned with the debugging entitlement, enabling enhanced
        /// backtraces on macOS.
        public var shouldEnableDebuggingEntitlement: Bool

        /// Whether to omit frame pointers
        public var omitFramePointers: Bool?
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
        guard configuration == .debug, prepareForIndexing == .off else {
            return nil
        }

        if self.triple.isApple() {
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
