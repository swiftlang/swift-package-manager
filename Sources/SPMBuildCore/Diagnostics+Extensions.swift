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
import enum PackageModel.BuildConfiguration
import struct PackageModel.PackageIdentity

extension Basics.Diagnostic {

    package static func unsupportedStripProductsConfigurationFlag(
        isEnabled: Bool,
        with selectedBuildSystem: BuildSystemProvider.Kind,
    ) -> Self {
        return .error("Command line option '--\(isEnabled ? "enable": "--disable")--experimental-strip-products' is unsupported with build system '\(selectedBuildSystem)'.  Only use with '\(BuildSystemProvider.Kind.swiftbuild)' build system with configuration '\(BuildConfiguration.release)'")
    }

    /// Diagnostic emitted when `--package X --product Y` names a valid
    /// workspace member but `Y` is not a product declared in that
    /// member. Lists the products the member does declare so the user
    /// can correct the invocation.
    @_spi(SwiftPMInternal)
    public static func unknownProductInMember(
        requested: String,
        package: PackageIdentity,
        known: Set<PackageIdentity>,
    ) -> Self {
        let sortedKnown = known.sorted()
        return .error(
            """
            no product named '\(requested)' in workspace member '\(package)'; \
            known products: \(sortedKnown.map { "'\($0.description)'" }.joined(separator: ", "))
            """,
        )
    }

    /// Diagnostic emitted when `--package X --target Y` names a valid
    /// workspace member but `Y` is not a target declared in that
    /// member. Lists the targets the member does declare so the user
    /// can correct the invocation.
    @_spi(SwiftPMInternal)
    public static func unknownTargetInMember(
        requested: String,
        package: PackageIdentity,
        known: Set<PackageIdentity>,
    ) -> Self {
        let sortedKnown = known.sorted()
        return .error(
            """
            no target named '\(requested)' in workspace member '\(package)'; \
            known targets: \(sortedKnown.map { "'\($0.description)'" }.joined(separator: ", "))
            """,
        )
    }
}
