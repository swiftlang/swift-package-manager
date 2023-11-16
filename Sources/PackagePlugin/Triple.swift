//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A type of machine on which code is build and/or executed. Usually includes information such as CPU architecture,
/// vendor name, operating system, ABI, and object file format among other possible features. Swift and SwiftPM use
/// Clang conventions for triple components and their naming.
public struct Triple: CustomStringConvertible {
    public let description: String
}
