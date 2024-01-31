//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import struct PackageGraph.ResolvedTarget

@_spi(SwiftPMInternal)
import SPMBuildCore

extension ResolvedTarget {
    func tempsPath(_ buildParameters: BuildParameters) -> AbsolutePath {
        buildParameters.buildPath.appending(component: self.c99name + "\(self.buildTriple.suffix).build")
    }
}
