/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

extension Diagnostic.Message {
    static func unusedDependency(_ name: String) -> Diagnostic.Message {
        .warning("dependency '\(name)' is not used by any target")
    }

    static func productUsesUnsafeFlags(product: String, target: String) -> Diagnostic.Message {
        .error("the target '\(target)' in product '\(product)' contains unsafe build flags")
    }
}
