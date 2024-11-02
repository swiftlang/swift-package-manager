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

import PackageModel
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Add a product to the manifest's source code.
public struct AddProduct {
    /// The set of argument labels that can occur after the "products"
    /// argument in the Package initializers.
    ///
    /// TODO: Could we generate this from the the PackageDescription module, so
    /// we don't have keep it up-to-date manually?
    private static let argumentLabelsAfterProducts: Set<String> = [
        "dependencies",
        "targets",
        "swiftLanguageVersions",
        "cLanguageStandard",
        "cxxLanguageStandard"
    ]

    /// Produce the set of source edits needed to add the given package
    /// dependency to the given manifest file.
    public static func addProduct(
        _ product: ProductDescription,
        to manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        // Make sure we have a suitable tools version in the manifest.
        try manifest.checkEditManifestToolsVersion()

        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        let newPackageCall = try packageCall.appendingToArrayArgument(
            label: "products",
            trailingLabels: argumentLabelsAfterProducts,
            newElement: product.asSyntax()
        )

        return PackageEditResult(
            manifestEdits: [
                .replace(packageCall, with: newPackageCall.description)
            ]
        )
    }
}
