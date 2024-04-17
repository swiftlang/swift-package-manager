//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SwiftSyntax
import SwiftParser

/// Default indent when we have to introduce indentation but have no context
/// to get it right.
let defaultIndent = TriviaPiece.spaces(4)

extension Trivia {
    /// Determine whether this trivia has newlines or not.
    var hasNewlines: Bool {
        contains { piece in
            if case .newlines = piece {
                return true
            } else {
                return false
            }
        }
    }
}

/// Syntax walker to find the first occurrence of a given node kind that
/// matches a specific predicate.
private class FirstNodeFinder<Node: SyntaxProtocol>: SyntaxAnyVisitor {
    var predicate: (Node) -> Bool
    var found: Node? = nil

    init(predicate: @escaping (Node) -> Bool) {
        self.predicate = predicate
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if found != nil {
            return .skipChildren
        }

        if let matchedNode = node.as(Node.self), predicate(matchedNode) {
            found = matchedNode
            return .skipChildren
        }

        return .visitChildren
    }
}

extension SyntaxProtocol {
    /// Find the first node of the Self type that matches the given predicate.
    static func findFirst(
        in node: some SyntaxProtocol,
        matching predicate: (Self) -> Bool
    ) -> Self? {
        withoutActuallyEscaping(predicate) { escapingPredicate in
            let visitor = FirstNodeFinder<Self>(predicate: escapingPredicate)
            visitor.walk(node)
            return visitor.found
        }
    }
}

extension FunctionCallExprSyntax {
    /// Check whether this call expression has a callee that is a reference
    /// to a declaration with the given name.
    func hasCallee(named name: String) -> Bool {
        guard let calleeDeclRef = calledExpression.as(DeclReferenceExprSyntax.self) else {
            return false
        }

        return calleeDeclRef.baseName.text == name
    }

    /// Find a call argument based on its label.
    func findArgument(labeled label: String) -> LabeledExprSyntax? {
        arguments.first { $0.label?.text == label }
    }
}

extension LabeledExprListSyntax {
    /// Find the index at which the one would insert a new argument given
    /// the set of argument labels that could come after the argument we
    /// want to insert.
    func findArgumentInsertionPosition(
        labelsAfter: Set<String>
    ) -> SyntaxChildrenIndex {
        firstIndex {
            guard let label = $0.label else {
                return false
            }

            return labelsAfter.contains(label.text)
        } ?? endIndex
    }

    /// Form a new argument list that inserts a new argument at the specified
    /// position in this argument list.
    ///
    /// This operation will attempt to introduce trivia to match the
    /// surrounding context where possible. The actual argument will be
    /// created by the `generator` function, which is provided with leading
    /// trivia and trailing comma it should use to match the surrounding
    /// context.
    func insertingArgument(
        at position: SyntaxChildrenIndex,
        generator: (Trivia, TokenSyntax?) -> LabeledExprSyntax
    ) -> LabeledExprListSyntax {
        // Turn the arguments into an array so we can manipulate them.
        var arguments = Array(self)

        let positionIdx = distance(from: startIndex, to: position)

        let commaToken = TokenSyntax(.comma, presence: .present)

        // Figure out leading trivia and adjust the prior argument (if there is
        // one) by adding a comma, if necessary.
        let leadingTrivia: Trivia
        if position > startIndex {
            let priorArgument = arguments[positionIdx - 1]

            // Our leading trivia will be based on the prior argument's leading
            // trivia.
            leadingTrivia = priorArgument.leadingTrivia

            // If the prior argument is missing a trailing comma, add one.
            if priorArgument.trailingComma == nil {
                arguments[positionIdx - 1].trailingComma = commaToken
            }
        } else if positionIdx + 1 < count {
            leadingTrivia = arguments[positionIdx + 1].leadingTrivia
        } else {
            leadingTrivia = Trivia()
        }

        // Determine whether we need a trailing comma on this argument.
        let trailingComma: TokenSyntax?
        if position < endIndex {
            trailingComma = commaToken
        } else {
            trailingComma = nil
        }

        // Create the argument and insert it into the argument list.
        let argument = generator(leadingTrivia, trailingComma)
        arguments.insert(argument, at: positionIdx)

        return LabeledExprListSyntax(arguments)
    }
}

extension SyntaxProtocol {
    /// Look for a call expression to a callee with the given name.
    func findCall(calleeName: String) -> FunctionCallExprSyntax? {
        return FunctionCallExprSyntax.findFirst(in: self) { call in
            return call.hasCallee(named: calleeName)
        }
    }
}

extension ArrayExprSyntax {
    /// Produce a new array literal expression that appends the given
    /// element, while trying to maintain similar indentation.
    func appending(
        element: ExprSyntax,
        outerLeadingTrivia: Trivia
    ) -> ArrayExprSyntax {
        var elements = self.elements

        let commaToken = TokenSyntax(.comma, presence: .present)

        // If there are already elements, tack it on.
        let leadingTrivia: Trivia
        let trailingTrivia: Trivia
        let leftSquareTrailingTrivia: Trivia
        if let last = elements.last {
            // The leading trivia of the new element should match that of the
            // last element.
            leadingTrivia = last.leadingTrivia

            // Add a trailing comma to the last element if it isn't already
            // there.
            if last.trailingComma == nil {
                var newElements = Array(elements)
                newElements[newElements.count-1] = last.with(\.trailingComma, commaToken)
                elements = ArrayElementListSyntax(newElements)
            }

            trailingTrivia = Trivia()
            leftSquareTrailingTrivia = leftSquare.trailingTrivia
        } else {
            leadingTrivia = outerLeadingTrivia.appending(defaultIndent)
            trailingTrivia = outerLeadingTrivia
            if leftSquare.trailingTrivia.hasNewlines {
                leftSquareTrailingTrivia = leftSquare.trailingTrivia
            } else {
                leftSquareTrailingTrivia = Trivia()
            }
        }

        elements.append(
            ArrayElementSyntax(
                expression: element.with(\.leadingTrivia, leadingTrivia),
                trailingComma: commaToken.with(\.trailingTrivia, trailingTrivia)
            )
        )

        let newLeftSquare = leftSquare.with(
            \.trailingTrivia,
             leftSquareTrailingTrivia
        )

        return with(\.elements, elements).with(\.leftSquare, newLeftSquare)
    }
}
