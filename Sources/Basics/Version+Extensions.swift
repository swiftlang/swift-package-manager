//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCUtility.Version

extension Version {
    /// Try a version from a git tag.
    ///
    /// - Parameter tag: A version string possibly prepended with "v".
    public init?(tag: String) {
        if tag.first == "v" {
            try? self.init(versionString: String(tag.dropFirst()), usesLenientParsing: true)
        } else {
            try? self.init(versionString: tag, usesLenientParsing: true)
        }
    }
}
