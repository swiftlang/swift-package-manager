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

import PackageAudit
import SwiftSyntax

import struct TSCUtility.Version

/// Identifies a dependency declared in a manifest by its source location or registry identity.
enum DependencyLocator: Equatable {
    case url(String)
    case id(String)
}

enum ManifestRequirementEditError: Error, Equatable {
    /// No `.package(...)` call declares the dependency.
    case dependencyNotFound
    /// More than one `.package(...)` call declares the dependency.
    case ambiguousDependency
    /// The requirement is not written with string literals (e.g. `from: someVersion`).
    case nonLiteralRequirement
    /// The requirement kind cannot express a version lower bound (e.g. `branch`, `revision`).
    case unsupportedRequirement(String)
}

/// Rewrites the version requirement of an existing dependency in a manifest's source.
enum ManifestRequirementEditor {
    /// Returns edits that raise the lower bound of `dependency`'s requirement to `version`,
    /// keeping the kind of requirement. Only the version string literals are replaced, so
    /// surrounding formatting and comments are preserved. Returns no edits when the
    /// requirement's lower bound is already at or above `version`.
    ///
    /// The whole file is searched for the `.package(...)` call, so dependencies declared in
    /// a variable outside of `Package(...)` are found too. Exactly one call must match.
    static func raiseLowerBound(
        in source: SourceFileSyntax,
        of dependency: DependencyLocator,
        to version: Version
    ) throws -> [SourceEdit] {
        let finder = PackageCallFinder(dependency: dependency)
        finder.walk(source)
        guard let call = finder.matches.first else {
            throw ManifestRequirementEditError.dependencyNotFound
        }
        guard finder.matches.count == 1 else {
            throw ManifestRequirementEditError.ambiguousDependency
        }
        return try self.requirementEdits(in: call.arguments, raisingTo: version)
    }

    private static func requirementEdits(
        in arguments: LabeledExprListSyntax,
        raisingTo version: Version
    ) throws -> [SourceEdit] {
        for argument in arguments {
            switch argument.label?.text {
            case "from", "exact":
                return try self.lowerBoundEdit(argument.expression, raisingTo: version)
            case let label? where label == "branch" || label == "revision":
                throw ManifestRequirementEditError.unsupportedRequirement(label)
            case "requirement", nil:
                return try self.requirementExpressionEdits(argument.expression, raisingTo: version)
            default:
                // Locator and other non-requirement arguments (name, url, id, traits, ...).
                continue
            }
        }
        throw ManifestRequirementEditError.unsupportedRequirement("missing")
    }

    /// Handles requirement expressions: `.upToNextMajor(from:)`, `.upToNextMinor(from:)`,
    /// `.exact(_:)` and version ranges.
    private static func requirementExpressionEdits(
        _ expression: ExprSyntax,
        raisingTo version: Version
    ) throws -> [SourceEdit] {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self)
        {
            let name = member.declName.baseName.text
            switch name {
            case "upToNextMajor", "upToNextMinor":
                guard let from = call.arguments.first(where: { $0.label?.text == "from" }) else {
                    throw ManifestRequirementEditError.unsupportedRequirement(name)
                }
                return try self.lowerBoundEdit(from.expression, raisingTo: version)
            case "exact":
                guard let value = call.arguments.first, call.arguments.count == 1 else {
                    throw ManifestRequirementEditError.unsupportedRequirement(name)
                }
                return try self.lowerBoundEdit(value.expression, raisingTo: version)
            default:
                throw ManifestRequirementEditError.unsupportedRequirement(name)
            }
        }

        // The parser leaves operators unfolded, so `"a"..<"b"` is a sequence expression;
        // accept a folded infix expression as well.
        if let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 3 {
            let elements = Array(sequence.elements)
            if let op = elements[1].as(BinaryOperatorExprSyntax.self) {
                return try self.rangeEdits(lower: elements[0], operator: op, upper: elements[2], raisingTo: version)
            }
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)
        {
            return try self.rangeEdits(
                lower: infix.leftOperand,
                operator: op,
                upper: infix.rightOperand,
                raisingTo: version
            )
        }

        if expression.is(StringLiteralExprSyntax.self) {
            // An unlabelled string is not a requirement form we know how to edit.
            throw ManifestRequirementEditError.unsupportedRequirement(expression.trimmedDescription)
        }
        if expression.is(DeclReferenceExprSyntax.self) || expression.is(MemberAccessExprSyntax.self) {
            throw ManifestRequirementEditError.nonLiteralRequirement
        }
        throw ManifestRequirementEditError.unsupportedRequirement(expression.trimmedDescription)
    }

    private static func rangeEdits(
        lower lowerExpression: ExprSyntax,
        operator op: BinaryOperatorExprSyntax,
        upper upperExpression: ExprSyntax,
        raisingTo version: Version
    ) throws -> [SourceEdit] {
        let isClosed: Bool
        switch op.operator.text {
        case "..<": isClosed = false
        case "...": isClosed = true
        default: throw ManifestRequirementEditError.unsupportedRequirement(op.operator.text)
        }
        let lower = try self.versionLiteral(lowerExpression)
        let upper = try self.versionLiteral(upperExpression)

        if let current = Version(lower.text), current >= version {
            return []
        }
        var edits = [self.replace(lower.literal, with: version)]
        if let upperVersion = Version(upper.text) {
            // Keep the range non-empty. A half-open range extends to the next major version;
            // a closed range only extends to `version`, so it never admits a new major version.
            if !isClosed, version >= upperVersion {
                edits.append(self.replace(upper.literal, with: Version(version.major + 1, 0, 0)))
            } else if isClosed, version > upperVersion {
                edits.append(self.replace(upper.literal, with: version))
            }
        }
        return edits
    }

    private static func lowerBoundEdit(_ expression: ExprSyntax, raisingTo version: Version) throws -> [SourceEdit] {
        let current = try self.versionLiteral(expression)
        if let currentVersion = Version(current.text), currentVersion >= version {
            return []
        }
        return [self.replace(current.literal, with: version)]
    }

    /// Extracts a plain string literal (no interpolation) used as a version.
    private static func versionLiteral(_ expression: ExprSyntax) throws -> (literal: StringLiteralExprSyntax, text: String) {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              let text = literal.plainText
        else {
            throw ManifestRequirementEditError.nonLiteralRequirement
        }
        return (literal, text)
    }

    /// Replaces the literal's token range only, leaving its surrounding trivia intact.
    private static func replace(_ literal: StringLiteralExprSyntax, with version: Version) -> SourceEdit {
        SourceEdit(
            range: literal.positionAfterSkippingLeadingTrivia ..< literal.endPositionBeforeTrailingTrivia,
            replacement: "\"\(version)\""
        )
    }
}

/// Collects `.package(...)` calls whose `url:` or `id:` literal matches a dependency.
private final class PackageCallFinder: SyntaxVisitor {
    let dependency: DependencyLocator
    private(set) var matches: [FunctionCallExprSyntax] = []

    init(dependency: DependencyLocator) {
        self.dependency = dependency
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "package",
           self.matches(node.arguments)
        {
            self.matches.append(node)
        }
        return .visitChildren
    }

    private func matches(_ arguments: LabeledExprListSyntax) -> Bool {
        for argument in arguments {
            guard let text = argument.expression.as(StringLiteralExprSyntax.self)?.plainText else {
                continue
            }
            switch (argument.label?.text, self.dependency) {
            case ("url", .url(let url)):
                if let lhs = SwiftURLName.normalize(text), let rhs = SwiftURLName.normalize(url) {
                    return lhs == rhs
                }
                return text == url
            case ("id", .id(let id)):
                return text.lowercased() == id.lowercased()
            default:
                continue
            }
        }
        return false
    }
}

extension StringLiteralExprSyntax {
    /// The literal's value when it has no interpolation, otherwise nil.
    fileprivate var plainText: String? {
        var text = ""
        for segment in self.segments {
            guard let plain = segment.as(StringSegmentSyntax.self) else { return nil }
            text += plain.content.text
        }
        return text
    }
}
