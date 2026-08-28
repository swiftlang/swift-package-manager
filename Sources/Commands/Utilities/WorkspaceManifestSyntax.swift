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
