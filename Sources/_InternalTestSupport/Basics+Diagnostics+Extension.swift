//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.Diagnostic

/// Test-only `Equatable` conformance for `Basics.Diagnostic`.
///
/// Production code intentionally does not conform `Diagnostic` to
/// `Equatable` — diagnostics carry attached `ObservabilityMetadata`
/// whose value equality is subtle (nested `AnyHashable` keys with
/// heterogeneous value types). Tests that just want to assert "the
/// same warning/error was emitted" don't need metadata parity, so
/// this conformance compares only the observable diagnostic surface:
/// severity and message.
///
/// If a test needs metadata equality, compare metadata explicitly
/// alongside the `==` check.
extension Basics.Diagnostic: @retroactive Equatable {
    public static func == (lhs: Basics.Diagnostic, rhs: Basics.Diagnostic) -> Bool {
        lhs.severity == rhs.severity && lhs.message == rhs.message
    }
}
