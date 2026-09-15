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
    /// `removeMember` was called with a path that isn't currently
    /// declared. Mirrors the `swift workspace override remove`
    /// behaviour so mistyped paths surface early instead of a silent
    /// no-op.
    case memberNotDeclared(String)

    public var description: String {
        switch self {
        case .cannotFindWorkspaceCall:
            return "could not find a `Workspace(...)` call in the source; is this a Workspace.swift file?"
        case .nonLiteralMemberEntry(let text):
            return "`members:` entry is not a plain string literal: \(text)"
        case .memberNotDeclared(let path):
            return "'\(path)' is not a declared workspace member"
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
    /// established by `swift workspace override list`.
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

    /// Parses `source` and returns the source-level
    /// `trimmedDescription` of each entry in the `dependencies:`
    /// array. Returns an empty list when the `dependencies:` argument
    /// is present-but-empty *or* omitted entirely (both shapes are
    /// legal for `Workspace(...)`). Callers use the returned strings
    /// to detect "already declared" without re-parsing individual
    /// requirement variants.
    /// - Throws: `WorkspaceManifestSyntaxError.cannotFindWorkspaceCall`
    ///   when the source has no `Workspace(...)` call.
    ///   `.nonLiteralMemberEntry` when `dependencies:` isn't a plain
    ///   array literal (dynamic composition is outside the edit
    ///   surface).
    public static func readDependencies(from source: String) throws -> [String] {
        let syntax = Parser.parse(source: source)
        guard let workspaceCall = findWorkspaceCall(in: syntax) else {
            throw WorkspaceManifestSyntaxError.cannotFindWorkspaceCall
        }
        guard let dependenciesArg = workspaceCall.arguments.first(where: {
            $0.label?.text == "dependencies"
        }) else {
            return []
        }
        guard let array = dependenciesArg.expression.as(ArrayExprSyntax.self) else {
            throw WorkspaceManifestSyntaxError.nonLiteralMemberEntry(
                dependenciesArg.expression.trimmedDescription,
            )
        }
        return array.elements.map { $0.expression.trimmedDescription }
    }

    /// Appends `dependencyExpression` (a `.package(...)` expression
    /// rendered as source text) to the `dependencies:` array of the
    /// `Workspace(...)` call in `source`, inserting the argument if
    /// it isn't present yet.
    ///
    /// - Idempotent: if an entry with the same trimmed source text
    ///   already appears in `dependencies:`, the returned string is
    ///   byte-identical to `source`.
    /// - Preserves formatting: existing entries, whitespace, and any
    ///   trailing-comma convention on the last element are kept
    ///   intact; the new element mirrors the last element's leading
    ///   trivia so indentation stays consistent.
    /// - Throws `.cannotFindWorkspaceCall` if the source has no
    ///   `Workspace(...)` call, or `.nonLiteralMemberEntry` if
    ///   `dependencies:` is present but isn't a plain array literal.
    public static func addDependency(
        _ dependencyExpression: String,
        to source: String,
    ) throws -> String {
        let syntax = Parser.parse(source: source)
        guard let workspaceCall = findWorkspaceCall(in: syntax) else {
            throw WorkspaceManifestSyntaxError.cannotFindWorkspaceCall
        }
        let dependencySyntax: ExprSyntax = "\(raw: dependencyExpression)"
        let newDependencyText = dependencySyntax.trimmedDescription

        if let existingArgIndex = workspaceCall.arguments.firstIndex(where: {
            $0.label?.text == "dependencies"
        }) {
            let existingArg = workspaceCall.arguments[existingArgIndex]
            guard let array = existingArg.expression.as(ArrayExprSyntax.self) else {
                throw WorkspaceManifestSyntaxError.nonLiteralMemberEntry(
                    existingArg.expression.trimmedDescription,
                )
            }
            let alreadyPresent = array.elements.contains(where: {
                $0.expression.trimmedDescription == newDependencyText
            })
            if alreadyPresent {
                return source
            }
            let newArray = appendExpressionElement(dependencySyntax, to: array)
            let rewriter = ReplaceArgumentExpression(
                targetLabel: "dependencies",
                newExpression: ExprSyntax(newArray),
            )
            let newTree = rewriter.rewrite(Syntax(syntax))
            return newTree.description
        }

        // No `dependencies:` argument yet — inject one after
        // `members:` in the same shape a hand-written manifest would
        // use, then populate it with the single new entry.
        let inserter = InsertDependenciesArgument(
            initialElement: dependencySyntax,
        )
        let newTree = inserter.rewrite(Syntax(syntax))
        return newTree.description
    }

    /// Shared helper for `addMember` and `addDependency`: appends an
    /// arbitrary `ExprSyntax` element to `array`, reusing the last
    /// existing element's leading trivia so indentation matches, and
    /// ensuring the previous last element carries a trailing comma.
    /// When the array is empty the new element is inserted as the
    /// sole entry with a standard 8-space indent.
    private static func appendExpressionElement(
        _ expression: ExprSyntax,
        to array: ArrayExprSyntax,
    ) -> ArrayExprSyntax {
        var mutable = Array(array.elements)
        if let lastIndex = mutable.indices.last {
            let lastElement = mutable[lastIndex]
            let newLastElement = lastElement.with(\.trailingComma, .commaToken())
            let newElement = ArrayElementSyntax(
                leadingTrivia: lastElement.leadingTrivia,
                expression: expression,
                trailingComma: .commaToken(),
                trailingTrivia: lastElement.trailingTrivia,
            )
            mutable[lastIndex] = newLastElement
            mutable.append(newElement)
            return array.with(\.elements, ArrayElementListSyntax(mutable))
        }
        let newElement = ArrayElementSyntax(
            leadingTrivia: .newline + .spaces(8),
            expression: expression,
            trailingComma: .commaToken(),
            trailingTrivia: .newline + .spaces(4),
        )
        return array.with(\.elements, ArrayElementListSyntax([newElement]))
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
        var mutable = Array(array.elements)
        if let lastIndex = mutable.indices.last {
            let lastElement = mutable[lastIndex]
            let newLastElement = lastElement.with(\.trailingComma, .commaToken())
            let newElement = ArrayElementSyntax(
                leadingTrivia: lastElement.leadingTrivia,
                expression: ExprSyntax(stringLiteral),
                trailingComma: .commaToken(),
                trailingTrivia: lastElement.trailingTrivia,
            )
            mutable[lastIndex] = newLastElement
            mutable.append(newElement)
            return array.with(\.elements, ArrayElementListSyntax(mutable))
        }
        let newElement = ArrayElementSyntax(
            leadingTrivia: .newline + .spaces(8),
            expression: ExprSyntax(stringLiteral),
            trailingComma: .commaToken(),
            trailingTrivia: .newline + .spaces(4),
        )
        return array.with(\.elements, ArrayElementListSyntax([newElement]))
    }

    /// Removes the member string-literal matching `member` from the
    /// `members:` array of the `Workspace(...)` call in `source`.
    ///
    /// - Throws `.cannotFindWorkspaceCall` if the source has no
    ///   `Workspace(...)` call.
    /// - Throws `.nonLiteralMemberEntry` if the `members:` argument
    ///   isn't a plain array literal.
    /// - Throws `.memberNotDeclared` if `member` doesn't appear in
    ///   `members:` — mirrors `swift workspace override
    ///   remove` so mistakes surface loudly.
    public static func removeMember(_ member: String, from source: String) throws -> String {
        let syntax = Parser.parse(source: source)
        guard let workspaceCall = findWorkspaceCall(in: syntax) else {
            throw WorkspaceManifestSyntaxError.cannotFindWorkspaceCall
        }
        guard let membersArgIndex = workspaceCall.arguments.firstIndex(where: {
            $0.label?.text == "members"
        }) else {
            throw WorkspaceManifestSyntaxError.memberNotDeclared(member)
        }
        let membersArg = workspaceCall.arguments[membersArgIndex]
        guard let array = membersArg.expression.as(ArrayExprSyntax.self) else {
            throw WorkspaceManifestSyntaxError.nonLiteralMemberEntry(
                membersArg.expression.trimmedDescription,
            )
        }
        let elements = Array(array.elements)
        guard let matchIndex = elements.firstIndex(where: { element in
            guard let literal = element.expression.as(StringLiteralExprSyntax.self),
                  let value = literal.representedLiteralValue
            else {
                return false
            }
            return value == member
        }) else {
            throw WorkspaceManifestSyntaxError.memberNotDeclared(member)
        }
        let newArray = removeElement(at: matchIndex, from: array)
        let rewriter = ReplaceArgumentExpression(
            targetLabel: "members",
            newExpression: ExprSyntax(newArray),
        )
        let newTree = rewriter.rewrite(Syntax(syntax))
        return newTree.description
    }

    /// Returns a new array literal with the element at `index`
    /// removed. When the removed element was the last one, the
    /// resulting array is empty. Trailing-comma handling on the new
    /// last element is normalized so the emitted source stays
    /// syntactically valid.
    private static func removeElement(
        at index: Int,
        from array: ArrayExprSyntax,
    ) -> ArrayExprSyntax {
        var remaining = Array(array.elements)
        remaining.remove(at: index)
        if remaining.isEmpty {
            return array.with(\.elements, ArrayElementListSyntax([]))
        }
        if let lastIndex = remaining.indices.last {
            remaining[lastIndex] = remaining[lastIndex].with(\.trailingComma, .commaToken())
        }
        return array.with(\.elements, ArrayElementListSyntax(remaining))
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

/// Inserts a fresh `dependencies:` argument onto the first
/// `Workspace(...)` call, populating it with a single element.
/// Placed after the existing `members:` argument so the resulting
/// manifest reads in the standard members-then-dependencies order.
/// A no-op if the enclosing `Workspace(...)` call already declares
/// `dependencies:` — the caller (`addDependency`) routes to
/// `ReplaceArgumentExpression` in that case.
private final class InsertDependenciesArgument: SyntaxRewriter {
    let initialElement: ExprSyntax
    private var applied = false

    init(initialElement: ExprSyntax) {
        self.initialElement = initialElement
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
        if node.arguments.contains(where: { $0.label?.text == "dependencies" }) {
            return super.visit(node)
        }
        applied = true

        // Build a fresh `dependencies: [ <initialElement>, ]` array
        // literal, matching the indentation style used by
        // `swift workspace init` (8-space element indent, 4-space
        // closing-bracket indent).
        let newElement = ArrayElementSyntax(
            leadingTrivia: .newline + .spaces(8),
            expression: initialElement,
            trailingComma: .commaToken(),
            trailingTrivia: [],
        )
        let arrayExpr = ArrayExprSyntax(
            leftSquare: .leftSquareToken(),
            elements: ArrayElementListSyntax([newElement]),
            rightSquare: .rightSquareToken(
                leadingTrivia: .newline + .spaces(4),
            ),
        )

        var arguments = Array(node.arguments)
        let membersIndex = arguments.firstIndex(where: { $0.label?.text == "members" })
        let insertAfter = membersIndex ?? (arguments.indices.last)
        let referenceElement = insertAfter.map { arguments[$0] }
        let leadingTrivia = referenceElement?.leadingTrivia ?? (.newline + .spaces(4))
        let trailingTrivia = referenceElement?.trailingTrivia ?? []

        // Ensure the reference element has a trailing comma so the
        // new argument can slot in behind it without breaking the
        // call's argument-list syntax.
        if let insertAfter, arguments[insertAfter].trailingComma == nil {
            arguments[insertAfter] = arguments[insertAfter].with(
                \.trailingComma, .commaToken(),
            )
        }

        let newArgument = LabeledExprSyntax(
            leadingTrivia: leadingTrivia,
            label: .identifier("dependencies"),
            colon: .colonToken(),
            expression: ExprSyntax(arrayExpr),
            trailingComma: .commaToken(),
            trailingTrivia: trailingTrivia,
        )
        let insertionIndex = (insertAfter.map { arguments.index(after: $0) }) ?? arguments.endIndex
        arguments.insert(newArgument, at: insertionIndex)
        return ExprSyntax(
            node.with(\.arguments, LabeledExprListSyntax(arguments)),
        )
    }
}
