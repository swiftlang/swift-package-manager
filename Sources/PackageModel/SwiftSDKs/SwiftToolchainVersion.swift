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

package struct SwiftToolchainVersion: Decodable {
    /// Since triples don't encode the platform, we use platform identifiers
    /// that match swift.org toolchain distribution names.
    enum Platform: Decodable {
        case macOS
        case ubuntu2004
        case ubuntu2204
        case ubuntu2404
        case debian12
        case amazonLinux2
        case fedora39
        case fedora41
        case ubi9
    }

    enum Architecture: Decodable {
        case aarch64
        case x86_64
    }

    /// A Git tag from which this toolchain was built.
    let tag: String

    /// CPU architecture on which this toolchain runs.
    let architecture: Architecture

    /// Platform identifier on which this toolchain runs.
    let platform: Platform
}
