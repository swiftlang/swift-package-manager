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

extension BuildParameters {
    /// An optional intermodule optimization to run at link time.
    ///
    /// When using Link Time Optimization (LTO for short) the swift and clang
    /// compilers produce objects containing containing a higher level
    /// representation of the program bitcode instead of machine code. The
    /// linker combines these objects together performing additional
    /// optimizations with visibility into each module/object, resulting in a
    /// further optimized version of the executable.
    ///
    /// Using LTO can have significant impact on compile times, however can be
    /// used to dramatically reduce code-size in some cases.
    ///
    /// Note: Bitcode objects and machine code objects can be linked together.
    public enum LinkTimeOptimizationMode: String, Encodable {
        /// The "standard" LTO mode designed to produce minimal code sign.
        ///
        /// Full LTO can lead to large link times. Consider using thin LTO if
        /// build time is more important than minimizing binary size.
        case full
        /// An LTO mode designed to scale better with input size.
        ///
        /// Thin LTO typically results in faster link times than traditional LTO.
        /// However, thin LTO may not result in binary as small as full LTO.
        case thin
    }

    /// Build parameters related to linking grouped in a single type to aggregate those in one place.
    public struct Linking: Encodable {
        /// Whether to disable dead code stripping by the linker
        public var linkerDeadStrip: Bool

        public var linkTimeOptimizationMode: LinkTimeOptimizationMode?

        /// Disables adding $ORIGIN/@loader_path to the rpath, useful when deploying
        public var shouldDisableLocalRpath: Bool

        /// If should link the Swift stdlib statically.
        public var shouldLinkStaticSwiftStdlib: Bool

        public init(
            linkerDeadStrip: Bool = true,
            linkTimeOptimizationMode: LinkTimeOptimizationMode? = nil,
            shouldDisableLocalRpath: Bool = false,
            shouldLinkStaticSwiftStdlib: Bool = false
        ) {
            self.linkerDeadStrip = linkerDeadStrip
            self.linkTimeOptimizationMode = linkTimeOptimizationMode
            self.shouldDisableLocalRpath = shouldDisableLocalRpath
            self.shouldLinkStaticSwiftStdlib = shouldLinkStaticSwiftStdlib
        }
    }
}

extension [String] {
    /// Converts a set of C compiler flags into an equivalent set to be
    /// indirected through the Swift compiler instead.
    public func asSwiftcCCompilerFlags() -> Self {
        self.flatMap { ["-Xcc", $0] }
    }

    /// Converts a set of C++ compiler flags into an equivalent set to be
    /// indirected through the Swift compiler instead.
    public func asSwiftcCXXCompilerFlags() -> Self {
        _ = self.flatMap { ["-Xcxx", $0] }
        // TODO: Pass -Xcxx flags to swiftc (#6491)
        // Remove fatal error when downstream support arrives.
        fatalError("swiftc does support -Xcxx flags yet.")
    }

    /// Converts a set of linker flags into an equivalent set to be indirected
    /// through the Swift compiler instead.
    ///
    /// Some arguments can be passed directly to the Swift compiler. We omit
    /// prefixing these arguments (in both the "-option value" and
    /// "-option[=]value" forms) with "-Xlinker". All other arguments are
    /// prefixed with "-Xlinker".
    public func asSwiftcLinkerFlags() -> Self {
        // Arguments that can be passed directly to the Swift compiler and
        // doesn't require -Xlinker prefix.
        //
        // We do this to avoid sending flags like linker search path at the end
        // of the search list.
        let directSwiftLinkerArgs = ["-L"]

        var flags: [String] = []
        var it = self.makeIterator()
        while let flag = it.next() {
            if directSwiftLinkerArgs.contains(flag) {
                // `<option> <value>` variant.
                flags.append(flag)
                guard let nextFlag = it.next() else {
                    // We expected a flag but don't have one.
                    continue
                }
                flags.append(nextFlag)
            } else if directSwiftLinkerArgs.contains(where: { flag.hasPrefix($0) }) {
                // `<option>[=]<value>` variant.
                flags.append(flag)
            } else {
                flags += ["-Xlinker", flag]
            }
        }
        return flags
    }
}
