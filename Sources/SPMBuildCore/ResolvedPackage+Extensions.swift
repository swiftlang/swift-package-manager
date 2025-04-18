//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel
import TSCUtility

import struct PackageGraph.ResolvedPackage
import struct PackageGraph.ResolvedModule

extension ResolvedPackage {
    @_spi(SwiftPMInternal)
    public func packageNameArgument(target: ResolvedModule, isPackageNameSupported: Bool) -> [String] {
        if self.manifest.usePackageNameFlag, target.packageAccess {
            ["-package-name", self.identity.description.spm_mangledToC99ExtendedIdentifier()]
        } else {
            []
        }
    }
}
