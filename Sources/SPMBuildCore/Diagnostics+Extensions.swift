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

    /// Diagnostic emitted when `swift run <name>` at the workspace root
    /// finds `<name>` declared as an executable in more than one
    /// workspace member. Lists each `(member, product)` candidate so
    /// the user can disambiguate with `--package <identity>`.
    @_spi(SwiftPMInternal)
    public static func ambiguousExecutable(
        requested: String,
        candidates: [(member: PackageIdentity, product: String)],
    ) -> Self {
        let sorted = candidates.sorted {
            ($0.product, $0.member.description) < ($1.product, $1.member.description)
        }
        let listing = sorted
            .map { "'\($0.product)' in member '\($0.member)'" }
            .joined(separator: ", ")
        return .error(
            """
            ambiguous executable '\(requested)' in workspace; candidates: \(listing); \
            select one with --package <identity>
            """,
        )
    }

    /// Diagnostic emitted when `swift run <name>` (or `swift run
    /// --package X <name>`) names an executable not declared by the
    /// member being searched. Lists the member's known executables so
    /// the user can correct the invocation.
    @_spi(SwiftPMInternal)
    public static func executableNotFoundInMember(
        requested: String,
        package: PackageIdentity,
        known: Set<PackageIdentity>,
    ) -> Self {
        let sortedKnown = known.sorted()
        return .error(
            """
            no executable named '\(requested)' in workspace member '\(package)'; \
            known executables: \(sortedKnown.map { "'\($0.description)'" }.joined(separator: ", "))
            """,
        )
    }

    /// Diagnostic emitted when `swift run <name>` names an executable
    /// declared by no workspace member. Lists each `(member,
    /// executable)` pair known to the workspace so the user can spot
    /// typos.
    @_spi(SwiftPMInternal)
    public static func executableNotFoundInWorkspace(
        requested: String,
        known: [PackageIdentity: Set<PackageIdentity>],
    ) -> Self {
        let listing = known
            .flatMap { member, execs in execs.map { (member, $0) } }
            .sorted { ($0.1.description, $0.0.description) < ($1.1.description, $1.0.description) }
            .map { "'\($0.1.description)' in member '\($0.0)'" }
            .joined(separator: ", ")
        let suffix = listing.isEmpty ? "no executables declared" : "known executables: \(listing)"
        return .error(
            """
            no executable named '\(requested)' in workspace; \(suffix)
            """,
        )
    }

    /// Diagnostic emitted when `swift run` (no explicit name) at the
    /// workspace root finds more than one executable across all
    /// members. Lists the candidates so the user can pick one with
    /// `swift run <name>` or `--package <identity>`.
    @_spi(SwiftPMInternal)
    public static func multipleExecutablesInWorkspace(
        candidates: [(member: PackageIdentity, product: String)],
    ) -> Self {
        let sorted = candidates.sorted {
            ($0.product, $0.member.description) < ($1.product, $1.member.description)
        }
        let listing = sorted
            .map { "'\($0.product)' in member '\($0.member)'" }
            .joined(separator: ", ")
        return .error(
            """
            multiple executables available in workspace: \(listing); \
            select one with `swift run <name>` or `--package <identity>`
            """,
        )
    }

    /// Diagnostic emitted when `swift run` (no explicit name) at the
    /// workspace root finds no executables in any member.
    @_spi(SwiftPMInternal)
    public static func noExecutableFoundInWorkspace() -> Self {
        .error("no executable product available in workspace")
    }

    /// Diagnostic emitted when `swift run` (no explicit name) is
    /// scoped to a specific workspace member (via `--package X` or
    /// CWD-inside-member focus) and that member declares no
    /// executables.
    @_spi(SwiftPMInternal)
    public static func noExecutableFoundInMember(package: PackageIdentity) -> Self {
        .error("no executable product available in workspace member '\(package)'")
    }
}
