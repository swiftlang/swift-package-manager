//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import TSCBasic

extension String {
    /// Escape the usual shell related things, such as quoting, but also handle Windows
    /// back-slashes.
    func shellEscaped() -> String {
        #if os(Windows)
        return self.spm_shellEscaped().replacingOccurrences(of: "\\", with: "/")
        #else
        return self.spm_shellEscaped()
        #endif
    }
}

extension Basics.AbsolutePath {
    /// Returns a string representation of the path which uses POSIX slashes even on Windows.
    ///
    /// This is necessary for some cases where tools may treat the `\` character as part of an escape sequence rather than a path separator even on Windows. Use sparingly.
    public var pathStringWithPosixSlashes: String {
        #if os(Windows)
        pathString.replacingOccurrences(of: "\\", with: "/")
        #else
        pathString
        #endif
    }
}
