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

import Basics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Errors raised while parsing or editing a `Workspace.swift` source
/// file.
public enum WorkspaceManifestSyntaxError: Error, CustomStringConvertible {
    /// The source does not contain a `Workspace(...)` call at the
    /// expected top level.
    case cannotFindWorkspaceCall
    /// A `members:` element is not a plain string literal. The CLI
    /// edit surface only supports literal-array manifests; dynamically
    /// composed member lists (`Workspace(members: computeMembers())`)
    /// must be edited by hand.
    case nonLiteralMemberEntry(String)

    public var description: String {
        switch self {
        case .cannotFindWorkspaceCall:
            return "could not find a `Workspace(...)` call in the source; is this a Workspace.swift file?"
        case .nonLiteralMemberEntry(let text):
            return "`members:` entry is not a plain string literal: \(text)"
        }
    }
}

/// Source-level reader and editor for `Workspace.swift`. Reads and
/// mutates the `members:` and `dependencies:` array-literal arguments
/// of the top-level `Workspace(...)` call. Callers whose manifests
/// compute those arrays dynamically (via helpers, closures, etc.) are
/// outside the supported edit surface and get a
/// `WorkspaceManifestSyntaxError.nonLiteralMemberEntry` diagnostic.
public enum WorkspaceManifestSyntax {
    /// Parses `source` and returns the string-literal entries of the
    /// `members:` array sorted alphabetically. Sorting the display
    /// output (rather than preserving declaration order) makes the
    /// CLI's `list-members` deterministic across manifests that
    /// declare members in different orders, and matches the pattern
    /// established by `swift package workspace override list`.
    /// - Throws: `WorkspaceManifestSyntaxError.cannotFindWorkspaceCall`
    ///   when the source has no `Workspace(...)` call at all;
    ///   `.nonLiteralMemberEntry` when an entry is not a plain string
    ///   literal.
    public static func readMembers(from source: String) throws -> [String] {
        let syntax = Parser.parse(source: source)
        guard let workspaceCall = findWorkspaceCall(in: syntax) else {
            throw WorkspaceManifestSyntaxError.cannotFindWorkspaceCall
        }
        guard let membersArg = workspaceCall.arguments.first(where: {
            $0.label?.text == "members"
        }) else {
            return []
        }
        guard let array = membersArg.expression.as(ArrayExprSyntax.self) else {
            throw WorkspaceManifestSyntaxError.nonLiteralMemberEntry(
                membersArg.expression.trimmedDescription,
            )
        }
        let members = try array.elements.map { element -> String in
            guard let literal = element.expression.as(StringLiteralExprSyntax.self),
                  let value = literal.representedLiteralValue
            else {
                throw WorkspaceManifestSyntaxError.nonLiteralMemberEntry(
                    element.expression.trimmedDescription,
                )
            }
            return value
        }
        return members.sorted()
    }

    /// Appends a new member string-literal to the `members:` array of
    /// the `Workspace(...)` call in `source`. Returns the resulting
    /// source text.
    ///
    /// - Idempotent: if `member` already appears in `members:`, the
    ///   returned string is byte-identical to `source`.
    /// - Preserves formatting: existing entries, whitespace, and any
    ///   trailing-comma convention on the last element are kept
    ///   intact; the new element mirrors the last element's leading
    ///   trivia so indentation stays consistent.
    /// - Throws `.cannotFindWorkspaceCall` if the source has no
    ///   `Workspace(...)` call, or `.nonLiteralMemberEntry` if the
    ///   `members:` argument isn't a plain array literal.
    public static func addMember(_ member: String, to source: String) throws -> String {
        let syntax = Parser.parse(source: source)
        guard let workspaceCall = findWorkspaceCall(in: syntax) else {
            throw WorkspaceManifestSyntaxError.cannotFindWorkspaceCall
        }
        guard let membersArgIndex = workspaceCall.arguments.firstIndex(where: {
            $0.label?.text == "members"
        }) else {
            throw WorkspaceManifestSyntaxError.cannotFindWorkspaceCall
        }
        let membersArg = workspaceCall.arguments[membersArgIndex]
        guard let array = membersArg.expression.as(ArrayExprSyntax.self) else {
            throw WorkspaceManifestSyntaxError.nonLiteralMemberEntry(
                membersArg.expression.trimmedDescription,
            )
        }
        let existingLiterals = array.elements.compactMap {
            $0.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }
        if existingLiterals.contains(member) {
            return source
        }
        let newArray = appendStringLiteralElement(member, to: array)
        let rewriter = ReplaceArgumentExpression(
            targetLabel: "members",
            newExpression: ExprSyntax(newArray),
        )
        let newTree = rewriter.rewrite(Syntax(syntax))
        return newTree.description
    }

    /// Builds a new array literal by appending a string-literal
    /// element to `array`. Reuses the last existing element's leading
    /// trivia so indentation matches, and ensures the previous last
    /// element carries a trailing comma. When the array is empty the
    /// new element is inserted as the sole entry.
    private static func appendStringLiteralElement(
        _ value: String,
        to array: ArrayExprSyntax,
    ) -> ArrayExprSyntax {
        let stringLiteral = StringLiteralExprSyntax(content: value)
        if let lastIndex = array.elements.indices.last {
            let lastElement = array.elements[lastIndex]
            let newLastElement = lastElement.with(\.trailingComma, .commaToken())
            let newElement = ArrayElementSyntax(
                leadingTrivia: lastElement.leadingTrivia,
                expression: ExprSyntax(stringLiteral),
                trailingComma: .commaToken(),
                trailingTrivia: lastElement.trailingTrivia,
            )
            var newElements = array.elements
            newElements = newElements.with(\.[lastIndex], newLastElement)
            newElements = newElements.appending(newElement)
            return array.with(\.elements, newElements)
        }
        let newElement = ArrayElementSyntax(
            leadingTrivia: .newline + .spaces(8),
            expression: ExprSyntax(stringLiteral),
            trailingComma: .commaToken(),
            trailingTrivia: .newline + .spaces(4),
        )
        return array.with(\.elements, ArrayElementListSyntax([newElement]))
    }

    /// Walks `syntax` looking for the first `Workspace(...)` function
    /// call — a top-level `let workspace = Workspace(...)` binding is
    /// the standard shape. Returns `nil` when no such call exists.
    private static func findWorkspaceCall(in syntax: some SyntaxProtocol) -> FunctionCallExprSyntax? {
        let finder = WorkspaceCallFinder()
        finder.walk(syntax)
        return finder.found
    }
}

private final class WorkspaceCallFinder: SyntaxVisitor {
    var found: FunctionCallExprSyntax?

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if found != nil {
            return .skipChildren
        }
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
           callee.baseName.text == "Workspace"
        {
            found = node
            return .skipChildren
        }
        return .visitChildren
    }
}

/// Replaces the expression of a labeled argument inside the first
/// `Workspace(...)` call. Used by the source-edit APIs to swap in a
/// new `members:` or `dependencies:` array literal while preserving
/// the surrounding manifest.
private final class ReplaceArgumentExpression: SyntaxRewriter {
    let targetLabel: String
    let newExpression: ExprSyntax
    private var applied = false

    init(targetLabel: String, newExpression: ExprSyntax) {
        self.targetLabel = targetLabel
        self.newExpression = newExpression
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        if applied {
            return super.visit(node)
        }
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "Workspace"
        else {
            return super.visit(node)
        }
        applied = true
        var arguments = node.arguments
        for index in arguments.indices where arguments[index].label?.text == targetLabel {
            arguments = arguments.with(
                \.[index],
                arguments[index].with(\.expression, newExpression),
            )
        }
        return ExprSyntax(node.with(\.arguments, arguments))
    }
}
