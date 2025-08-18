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

import enum PackageModel.BuildConfiguration

extension BuildConfiguration {

    public var buildFor: String {
        switch self {
        case .debug:
            return "debugging"
        case .release:
            return "production"
        }
    }
}
