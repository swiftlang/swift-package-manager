//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

/// Process-wide switch for the multiple-major-versions prototype.
///
/// Off by default, in which case SwiftPM resolves and loads packages exactly as it did before the prototype
/// (two requirements on different majors of the same package are an ordinary resolution error). It is turned on
/// once at startup by `--experimental-multiple-major-versions`.
///
/// This is deliberately a global rather than a value threaded through the call graph: the prototype is consulted
/// from model types (e.g. `PackageDependency`), the resolver, the graph loader and the workspace, none of which
/// share a configuration object. Anything that turns it on (e.g. a test) should restore it afterwards.
public enum MultiMajorVersions {
    private static let enabled = ThreadSafeBox<Bool>(false)

    /// Whether the multiple-major-versions prototype is active.
    public static var isEnabled: Bool {
        get { self.enabled.get() }
        set { self.enabled.mutate { (value: inout Bool) in value = newValue } }
    }

    /// Prints a prototype trace message (the `[MultiMajor]...` lines), only when the prototype is enabled.
    public static func log(_ message: @autoclosure () -> String) {
        guard self.isEnabled else { return }
        print(message())
    }
}
