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

/// The level at which a compiler warning should be treated.
///
/// This enum is used with the `SwiftSetting.treatAllWarnings(as:_:)` and 
/// `SwiftSetting.treatWarning(name:as:_:)` methods to control how warnings
/// are handled during compilation.
@available(_PackageDescription, introduced: 6.2)
public enum WarningLevel: String {
    /// Treat as a warning.
    ///
    /// Warnings will be displayed during compilation but will not cause the build to fail.
    case warning

    /// Treat as an error.
    ///
    /// Warnings will be elevated to errors, causing the build to fail if any such warnings occur.
    case error
}
