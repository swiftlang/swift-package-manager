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
import PackageModel
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Add a target to a manifest's source code.
public struct AddTarget {
    /// The set of argument labels that can occur after the "targets"
    /// argument in the Package initializers.
    ///
    /// TODO: Could we generate this from the the PackageDescription module, so
    /// we don't have keep it up-to-date manually?
    private static let argumentLabelsAfterTargets: Set<String> = [
        "swiftLanguageVersions",
        "cLanguageStandard",
        "cxxLanguageStandard"
    ]

    public static func addTarget(
        _ target: TargetDescription,
        to manifest: SourceFileSyntax
    ) throws -> [SourceEdit] {
        // Make sure we have a suitable tools version in the manifest.
        try manifest.checkEditManifestToolsVersion()

        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        return try packageCall.appendingToArrayArgument(
            label: "targets",
            trailingLabels: Self.argumentLabelsAfterTargets,
            newElement: target.asSyntax()
        )
    }
}
