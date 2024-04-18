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
        to manifest: SourceFileSyntax,
        manifestDirectory: AbsolutePath
    ) throws -> [SourceEdit] {
        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        let dependencySyntax = dependency.asSyntax(manifestDirectory: manifestDirectory)

        // If there is already a "dependencies" argument, append to the array
        // literal in there.
        if let dependenciesArg = packageCall.findArgument(labeled: "dependencies") {
            guard let argArray = dependenciesArg.expression.findArrayArgument() else {
                throw ManifestEditError.cannotFindArrayLiteralArgument(
                    argumentName: "dependencies",
                    node: Syntax(dependenciesArg.expression)
                )
            }

            let updatedArgArray = argArray.appending(
                element: dependencySyntax,
                outerLeadingTrivia: dependenciesArg.leadingTrivia
            )
            return [ .replace(argArray, with: updatedArgArray.description) ]
        }

        // There was no "dependencies" argument, so we need to create one.

        // Insert the new argument at the appropriate place in the call.
        let insertionPos = packageCall.arguments.findArgumentInsertionPosition(
            labelsAfter: Self.argumentLabelsAfterDependencies
        )
        let newArguments = packageCall.arguments.insertingArgument(
            at: insertionPos
        ) { (leadingTrivia, trailingComma) in
            // The argument is always [ element ], but if we have any newlines
            // in the leading trivia, then we really want to split it across
            // multiple lines, like this:
            // [
            //   element
            // ]
            let newArgument: ExprSyntax
            if !leadingTrivia.hasNewlines  {
                newArgument = " [ \(dependencySyntax), ]"
            } else {
                let innerTrivia = leadingTrivia.appending(defaultIndent)
                let arrayExpr = ArrayExprSyntax(
                    leadingTrivia: .space,
                    elements: [
                        ArrayElementSyntax(
                            leadingTrivia: innerTrivia,
                            expression: dependencySyntax,
                            trailingComma: .commaToken()
                        )
                    ],
                    rightSquare: .rightSquareToken()
                        .with(\.leadingTrivia, leadingTrivia)
                )
                newArgument = ExprSyntax(arrayExpr)
            }

            return LabeledExprSyntax(
                leadingTrivia: leadingTrivia,
                label: "dependencies", 
                colon: .colonToken(),
                expression: newArgument,
                trailingComma: trailingComma
            )
        }

        return [
            SourceEdit.replace(
                packageCall.arguments,
                with: newArguments.description
            )
        ]
    }
}
