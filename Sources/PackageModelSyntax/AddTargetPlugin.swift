//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
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

/// Add a target plugin to a manifest's source code.
public enum AddTargetPlugin {
    /// The set of argument labels that can occur after the "plugins"
    /// argument in the various target initializers.
    ///
    /// TODO: Could we generate this from the the PackageDescription module, so
    /// we don't have keep it up-to-date manually?
    private static let argumentLabelsAfterDependencies: Set<String> = []

    /// Produce the set of source edits needed to add the given target
    /// plugin to the given manifest file.
    public static func addTargetPlugin(
        _ plugin: TargetDescription.PluginUsage,
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
                let literalValue = stringLiteral.representedLiteralValue
            else {
                return false
            }

            return literalValue == targetName
        }

        guard let targetCall = FunctionCallExprSyntax.findFirst(
            in: targetArray,
            matching: matchesTargetCall
        ) else {
            throw ManifestEditError.cannotFindTarget(targetName: targetName)
        }

        guard try !self.pluginAlreadyAdded(
                plugin,
                to: targetName,
                in: targetCall
            )
        else {
            return PackageEditResult(manifestEdits: [])
        }

        let newTargetCall = try addTargetPluginLocal(
            plugin,
            to: targetCall
        )

        return PackageEditResult(
            manifestEdits: [
                .replace(targetCall, with: newTargetCall.description)
            ]
        )
    }

    private static func pluginAlreadyAdded(
        _ plugin: TargetDescription.PluginUsage,
        to targetName: String,
        in packageCall: FunctionCallExprSyntax
    ) throws -> Bool {
        let pluginSyntax = plugin.asSyntax()
        guard let pluginFnSyntax = pluginSyntax.as(FunctionCallExprSyntax.self)
        else {
            throw ManifestEditError.cannotFindPackage
        }

        guard let id = pluginFnSyntax.arguments.first(where: {
                $0.label?.text == "name"
            })
        else {
            throw InternalError("Missing 'name' argument in plugin syntax")
        }

        if let existingPlugins = packageCall.findArgument(labeled: "plugins") {
            // If we have an existing plugins array, we need to check if
            if let expr = existingPlugins.expression.as(ArrayExprSyntax.self) {
                // Iterate through existing plugins and look for an argument that matches
                // the `name` argument of the new plugin.
                let existingArgument = expr.elements.first { elem in
                    if let funcExpr = elem.expression.as(
                        FunctionCallExprSyntax.self
                    ) {
                        return funcExpr.arguments.contains {
                            $0.with(\.trailingComma, nil).trimmedDescription ==
                            id.with(\.trailingComma, nil).trimmedDescription
                        }
                    }
                    return true
                }

                if let existingArgument {
                    let normalizedExistingArgument = existingArgument.detached.with(\.trailingComma, nil)
                    // This exact plugin already exists, return false to indicate we should do nothing.
                    if normalizedExistingArgument.trimmedDescription == pluginSyntax.trimmedDescription {
                        return true
                    }
                    throw ManifestEditError.existingPlugin(
                        pluginName: plugin.identifier,
                        taget: targetName
                    )
                }
            }
        }

        return false
    }

    /// Implementation of adding a target plugin to an existing call.
    static func addTargetPluginLocal(
        _ plugin: TargetDescription.PluginUsage,
        to targetCall: FunctionCallExprSyntax
    ) throws -> FunctionCallExprSyntax {
        try targetCall.appendingToArrayArgument(
            label: "plugins",
            trailingLabels: self.argumentLabelsAfterDependencies,
            newElement: plugin.asSyntax()
        )
    }
}

extension TargetDescription.PluginUsage {
    fileprivate var identifier: String {
        switch self {
        case .plugin(let name, _):
            name
        }
    }
}
