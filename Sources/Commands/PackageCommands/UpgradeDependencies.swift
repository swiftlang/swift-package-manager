//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import PackageGraph
import PackageModel
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax
import Workspace

import struct TSCUtility.Version

extension SwiftPackageCommand {
    /// Rewrites every `from:` or `exact:` version requirement in the package
    /// manifest to its latest released version, including new major versions.
    ///
    /// Path, branch, revision, and registry dependencies are left untouched —
    /// the underlying `UpgradePackageDependencies` refactor only applies to
    /// remote source-control dependencies with an `url:` parameter and a
    /// `from:` or `exact:` version requirement.
    struct UpgradeDependencies: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "upgrade-dependencies",
            abstract: "Upgrade all package dependencies with `from:` or `exact:` version requirements to their latest released version, including new major versions.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let (manifestSyntax, manifestPath) = try swiftCommandState.readPackageManifestAsSyntaxTree()
            let workspace = try swiftCommandState.getActiveWorkspace()

            let observabilityScope = swiftCommandState.observabilityScope
            let context = try await UpgradePackageDependencies.Context(
                resolvingLatestVersionIn: manifestSyntax
            ) { url, currentVersion in
                await workspace.latestVersion(
                    of: url,
                    currentVersion: currentVersion,
                    observabilityScope: observabilityScope
                )
            }

            let edits = try UpgradePackageDependencies.textRefactor(syntax: manifestSyntax, in: context)

            try edits.applyEdits(
                to: workspace.fileSystem,
                manifest: manifestSyntax,
                manifestPath: manifestPath,
                verbose: !self.globalOptions.logging.quiet
            )
        }
    }
}

fileprivate extension Workspace {
    /// Returns the latest released version of the package at `url` that the
    /// caller is willing to upgrade to, or `nil` if it cannot be resolved.
    ///
    /// Pre-release versions (those with a SemVer pre-release suffix such as
    /// `-alpha.1`) are excluded when `currentVersion` is itself not a
    /// pre-release: a manifest pinned to `4.115.0` should not silently
    /// follow a freshly-published `5.0.0-alpha.1`. When `currentVersion` is
    /// already a pre-release the latest available version is returned, even
    /// if it is itself a pre-release.
    func latestVersion(
        of url: String,
        currentVersion: String,
        observabilityScope: ObservabilityScope
    ) async -> String? {
        let sourceControlURL = SourceControlURL(url)
        let identity = PackageIdentity(url: sourceControlURL)
        let reference = PackageReference.remoteSourceControl(identity: identity, url: sourceControlURL)
        // If the current version literal does not parse as a SemVer, treat it
        // as a release for the purposes of this filter: hiding pre-releases is
        // the safer default for the kinds of unparseable values seen in the
        // wild (e.g. partially-edited manifests).
        let allowsPrereleases = Version(currentVersion).map { !$0.prereleaseIdentifiers.isEmpty } ?? false
        do {
            let container = try await self.getContainer(
                for: reference,
                updateStrategy: .always,
                observabilityScope: observabilityScope
            )
            return try await container.toolsVersionsAppropriateVersionsDescending()
                .first(where: { allowsPrereleases || $0.prereleaseIdentifiers.isEmpty })?.description
        } catch {
            observabilityScope.emit(
                warning: "could not resolve latest version of \(url): \(error.interpolationDescription)"
            )
            return nil
        }
    }
}
