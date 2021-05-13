/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCUtility

extension Version {
    /// Try a version from a git tag.
    ///
    /// - Parameter tag: A version string possibly prepended with "v".
    public init?(tag: String) {
        if tag.first == "v" {
            self.init(string: String(tag.dropFirst()))
        } else {
            self.init(string: tag)
        }
    }
}
