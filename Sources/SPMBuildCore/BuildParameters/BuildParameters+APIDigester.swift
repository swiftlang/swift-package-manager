//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

extension BuildParameters {
    public enum APIDigesterMode: Encodable {
        case generateBaselines(baselinesDirectory: AbsolutePath, modulesRequestingBaselines: Set<String>)
        case compareToBaselines(baselinesDirectory: AbsolutePath, modulesToCompare: Set<String>, breakageAllowListPath: AbsolutePath?)
    }
}
