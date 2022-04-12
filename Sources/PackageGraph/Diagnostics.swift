//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

extension Basics.Diagnostic {
    static func unusedDependency(_ name: String) -> Self {
        .warning("dependency '\(name)' is not used by any target")
    }

    static func productUsesUnsafeFlags(product: String, target: String) -> Self {
        .error("the target '\(target)' in product '\(product)' contains unsafe build flags")
    }
}
