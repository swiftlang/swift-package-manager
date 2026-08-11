//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import struct Basics.Diagnostic
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration

extension Basics.Diagnostic {

    package static func unsupportedStripProductsConfigurationFlag(
        isEnabled: Bool,
        with selectedBuildSystem: BuildSystemProvider.Kind,
    ) -> Self {
        return .error("Command line option '--\(isEnabled ? "enable": "--disable")--experimental-strip-products' is unsupported with build system '\(selectedBuildSystem)'.  Only use with '\(BuildSystemProvider.Kind.swiftbuild)' build system with configuration '\(BuildConfiguration.release)'")
    }
}
