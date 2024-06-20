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

/// Add a target dependency to a manifest's source code.
public struct AddTargetDependency {
    /// The set of argument labels that can occur after the "dependencies"
    /// argument in the various target initializers.
    ///
    /// TODO: Could we generate this from the the PackageDescription module, so
    /// we don't have keep it up-to-date manually?
    private static let argumentLabelsAfterDependencies: Set<String> = [
        "path",
        "exclude",
        "sources",
        "resources",
        "publicHeadersPath",
        "packageAccess",
        "cSettings",
        "cxxSettings",
        "swiftSettings",
        "linkerSettings",
        "plugins",
    ]

    /// Produce the set of source edits needed to add the given target
    /// dependency to the given manifest file.
    public static func addTargetDependency(
        _ dependency: TargetDescription.Dependency,
        targetName: String,
        to manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        // Make sure we have a suitable tools version in the manifest.
        try manifest.checkEditManifestToolsVersion()

        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        // Dig out the array of targets.
        guard let targetsArgument = packageCall.findArgument(labeled: "targets"),
              let targetArray = targetsArgument.expression.findArrayArgument() else {
            throw ManifestEditError.cannotFindTargets
        }

        // Look for a call whose name is a string literal matching the
        // requested target name.
        func matchesTargetCall(call: FunctionCallExprSyntax) -> Bool {
            guard let nameArgument = call.findArgument(labeled: "name") else {
                return false
            }

            guard let stringLiteral = nameArgument.expression.as(StringLiteralExprSyntax.self),
                let literalValue = stringLiteral.representedLiteralValue else {
                return false
            }

            return literalValue == targetName
        }

        guard let targetCall = FunctionCallExprSyntax.findFirst(in: targetArray, matching: matchesTargetCall) else {
            throw ManifestEditError.cannotFindTarget(targetName: targetName)
        }

        let newTargetCall = try addTargetDependencyLocal(
            dependency, to: targetCall
        )

        return PackageEditResult(
            manifestEdits: [
                .replace(targetCall, with: newTargetCall.description)
            ]
        )
    }

    /// Implementation of adding a target dependency to an existing call.
    static func addTargetDependencyLocal(
        _ dependency: TargetDescription.Dependency,
        to targetCall: FunctionCallExprSyntax
    ) throws -> FunctionCallExprSyntax {
        try targetCall.appendingToArrayArgument(
            label: "dependencies",
            trailingLabels: Self.argumentLabelsAfterDependencies,
            newElement: dependency.asSyntax()
        )
    }
}

