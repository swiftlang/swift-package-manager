//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Add a package dependency to a manifest's source code.
public struct AddPackageDependency {
    /// The set of argument labels that can occur after the "dependencies"
    /// argument in the Package initializers.
    ///
    /// TODO: Could we generate this from the the PackageDescription module, so
    /// we don't have keep it up-to-date manually?
    private static let argumentLabelsAfterDependencies: Set<String> = [
        "targets",
        "swiftLanguageVersions",
        "cLanguageStandard",
        "cxxLanguageStandard"
    ]

    /// Produce the set of source edits needed to add the given package
    /// dependency to the given manifest file.
    public static func addPackageDependency(
        _ dependency: PackageDependency,
        to manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        // Make sure we have a suitable tools version in the manifest.
        try manifest.checkEditManifestToolsVersion()

        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        let edits = try packageCall.appendingToArrayArgument(
            label: "dependencies",
            trailingLabels: Self.argumentLabelsAfterDependencies,
            newElement: dependency.asSyntax()
        )

        return PackageEditResult(manifestEdits: edits)
    }
}
