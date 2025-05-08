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
import PackageModel
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import struct TSCUtility.Version

/// Add a swift setting to a manifest's source code.
public enum AddSwiftSetting {
    /// The set of argument labels that can occur after the "targets"
    /// argument in the Package initializers.
    private static let argumentLabelsAfterSwiftSettings: Set<String> = [
        "linkerSettings",
        "plugins",
    ]

    public static func upcomingFeature(
        to target: String,
        name: String,
        manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        try self.addToTarget(
            target,
            name: "enableUpcomingFeature",
            value: name,
            firstIntroduced: .v5_8,
            manifest: manifest
        )
    }

    public static func experimentalFeature(
        to target: String,
        name: String,
        manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        try self.addToTarget(
            target,
            name: "enableExperimentalFeature",
            value: name,
            firstIntroduced: .v5_8,
            manifest: manifest
        )
    }

    public static func languageMode(
        to target: String,
        mode: SwiftLanguageVersion,
        manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        try self.addToTarget(
            target,
            name: "swiftLanguageMode",
            value: mode,
            firstIntroduced: .v6_0,
            manifest: manifest
        )
    }

    public static func strictMemorySafety(
        to target: String,
        manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        try self.addToTarget(
            target, name: "strictMemorySafety",
            value: String?.none,
            firstIntroduced: .v6_2,
            manifest: manifest
        )
    }

    private static func addToTarget(
        _ target: String,
        name: String,
        value: (some ManifestSyntaxRepresentable)?,
        firstIntroduced: ToolsVersion,
        manifest: SourceFileSyntax
    ) throws -> PackageEditResult {
        try manifest.checkManifestAtLeast(firstIntroduced)

        guard let packageCall = manifest.findCall(calleeName: "Package") else {
            throw ManifestEditError.cannotFindPackage
        }

        guard let targetsArgument = packageCall.findArgument(labeled: "targets"),
              let targetArray = targetsArgument.expression.findArrayArgument()
        else {
            throw ManifestEditError.cannotFindTargets
        }

        guard let targetCall = FunctionCallExprSyntax.findFirst(in: targetArray, matching: {
            if let nameArgument = $0.findArgument(labeled: "name"),
               let nameLiteral = nameArgument.expression.as(StringLiteralExprSyntax.self),
               nameLiteral.representedLiteralValue == target
            {
                return true
            }
            return false
        }) else {
            throw ManifestEditError.cannotFindTarget(targetName: target)
        }

        if let memberRef = targetCall.calledExpression.as(MemberAccessExprSyntax.self),
           memberRef.declName.baseName.text == "plugin"
        {
            throw ManifestEditError.cannotAddSettingsToPluginTarget
        }

        let newTargetCall = if let value {
            try targetCall.appendingToArrayArgument(
                label: "swiftSettings",
                trailingLabels: self.argumentLabelsAfterSwiftSettings,
                newElement: ".\(raw: name)(\(value.asSyntax()))"
            )
        } else {
            try targetCall.appendingToArrayArgument(
                label: "swiftSettings",
                trailingLabels: self.argumentLabelsAfterSwiftSettings,
                newElement: ".\(raw: name)"
            )
        }

        return PackageEditResult(
            manifestEdits: [
                .replace(targetCall, with: newTargetCall.description),
            ]
        )
    }
}

extension SwiftLanguageVersion: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        if !Self.supportedSwiftLanguageVersions.contains(self) {
            return ".version(\"\(raw: rawValue)\")"
        }

        if minor == 0 {
            return ".v\(raw: major)"
        }

        return ".v\(raw: major)_\(raw: minor)"
    }
}
