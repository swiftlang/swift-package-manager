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
public enum AddPackageDependency {
    /// The set of argument labels that can occur after the "dependencies"
    /// argument in the Package initializers.
    ///
    /// TODO: Could we generate this from the the PackageDescription module, so
    /// we don't have keep it up-to-date manually?
    private static let argumentLabelsAfterDependencies: Set<String> = [
        "targets",
        "swiftLanguageVersions",
        "cLanguageStandard",
        "cxxLanguageStandard",
    ]

    /// Produce the set of source edits needed to add the given package
    /// dependency to the given manifest file.
    public static func addPackageDependency(
        _ dependency: MappablePackageDependency.Kind,
        to manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        // Make sure we have a suitable tools version in the manifest.
        try manifest.checkEditManifestToolsVersion()

        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        guard try !dependencyAlreadyAdded(
            dependency,
            in: packageCall
        ) else {
            return PackageEditResult(manifestEdits: [])
        }

        let newPackageCall = try addPackageDependencyLocal(
            dependency, to: packageCall
        )

        return PackageEditResult(
            manifestEdits: [
                .replace(packageCall, with: newPackageCall.description),
            ]
        )
    }

    /// Return `true` if the dependency already exists in the manifest, otherwise return `false`.
    /// Throws an error if a dependency already exists with the same id or url, but different arguments.
    private static func dependencyAlreadyAdded(
        _ dependency: MappablePackageDependency.Kind,
        in packageCall: FunctionCallExprSyntax
    ) throws -> Bool {
        let dependencySyntax = dependency.asSyntax()
        guard let dependenctFnSyntax = dependencySyntax.as(FunctionCallExprSyntax.self) else {
            throw ManifestEditError.cannotFindPackage
        }

        guard let id = dependenctFnSyntax.arguments.first(where: {
            $0.label?.text == "url" || $0.label?.text == "id" || $0.label?.text == "path"
        }) else {
            throw InternalError("Missing id or url argument in dependency syntax")
        }

        if let existingDependencies = packageCall.findArgument(labeled: "dependencies") {
            // If we have an existing dependencies array, we need to check if
            if let expr = existingDependencies.expression.as(ArrayExprSyntax.self) {
                // Iterate through existing dependencies and look for an argument that matches
                // either the `id` or `url` argument of the new dependency. 
                let existingArgument = expr.elements.first { elem in
                    if let funcExpr = elem.expression.as(FunctionCallExprSyntax.self) {
                        return funcExpr.arguments.contains {
                            $0.trimmedDescription == id.trimmedDescription
                        }
                    }
                    return true
                }

                if let existingArgument {
                    let normalizedExistingArgument = existingArgument.detached.with(\.trailingComma, nil)
                    // This exact dependency already exists, return false to indicate we should do nothing.
                    if normalizedExistingArgument.trimmedDescription == dependencySyntax.trimmedDescription {
                        return true
                    }
                    throw ManifestEditError.existingDependency(dependencyName: dependency.identifier)
                }
            }
        }
        return false
    }

    /// Implementation of adding a package dependency to an existing call.
    static func addPackageDependencyLocal(
        _ dependency: MappablePackageDependency.Kind,
        to packageCall: FunctionCallExprSyntax
    ) throws -> FunctionCallExprSyntax {
        try packageCall.appendingToArrayArgument(
            label: "dependencies",
            trailingLabels: self.argumentLabelsAfterDependencies,
            newElement: dependency.asSyntax()
        )
    }
}

fileprivate extension MappablePackageDependency.Kind {
    var identifier: String {
        switch self {
            case .sourceControl(let name, let path, _):
                return name ?? path
            case .fileSystem(let name, let location):
                return name ?? location
            case .registry(let id, _):
                return id
        }
    }
}
