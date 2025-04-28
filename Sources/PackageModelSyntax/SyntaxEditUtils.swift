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
import SwiftBasicFormat
import SwiftSyntax
import SwiftParser
import SwiftSyntaxBuilder

/// Default indent when we have to introduce indentation but have no context
/// to get it right.
let defaultIndent = TriviaPiece.spaces(4)

extension Trivia {
    /// Determine whether this trivia has newlines or not.
    var hasNewlines: Bool {
        contains(where: \.isNewline)
    }

    /// Produce trivia from the last newline to the end, dropping anything
    /// prior to that.
    func onlyLastLine() -> Trivia {
        guard let lastNewline = pieces.lastIndex(where: { $0.isNewline }) else {
            return self
        }

        return Trivia(pieces: pieces[lastNewline...])
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

    /// Find a call argument index based on its label.
    func findArgumentIndex(labeled label: String) -> LabeledExprListSyntax.Index? {
        arguments.firstIndex { $0.label?.text == label }
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

        let commaToken = TokenSyntax.commaToken()

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

        let commaToken = TokenSyntax.commaToken()

        // If there are already elements, tack it on.
        let leadingTrivia: Trivia
        let trailingTrivia: Trivia
        let leftSquareTrailingTrivia: Trivia
        if let last = elements.last {
            // The leading trivia of the new element should match that of the
            // last element.
            leadingTrivia = last.leadingTrivia.onlyLastLine()

            // Add a trailing comma to the last element if it isn't already
            // there.
            if last.trailingComma == nil {
                var newElements = Array(elements)
                newElements[newElements.count - 1].trailingComma = commaToken
                newElements[newElements.count - 1].expression.trailingTrivia =
                    Trivia()
                newElements[newElements.count - 1].trailingTrivia = last.trailingTrivia
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

extension ExprSyntax {
    /// Find an array argument either at the top level or within a sequence
    /// expression.
    func findArrayArgument() -> ArrayExprSyntax? {
        if let arrayExpr = self.as(ArrayExprSyntax.self) {
            return arrayExpr
        }

        if let sequenceExpr = self.as(SequenceExprSyntax.self) {
            return sequenceExpr.elements.lazy.compactMap {
                $0.findArrayArgument()
            }.first
        }

        return nil
    }
}

// MARK: Utilities to oeprate on arrays of array literal elements.
extension Array<ArrayElementSyntax> {
    /// Append a new argument expression.
    mutating func append(expression: ExprSyntax) {
        // Add a comma on the prior expression, if there is one.
        let leadingTrivia: Trivia?
        if count > 0 {
            self[count - 1].trailingComma = TokenSyntax.commaToken()
            leadingTrivia = .newline

            // Adjust the first element to start with a newline
            if count == 1 {
                self[0].leadingTrivia = .newline
            }
        } else {
            leadingTrivia = nil
        }

        append(
            ArrayElementSyntax(
                leadingTrivia: leadingTrivia,
                expression: expression
            )
        )
    }
}

// MARK: Utilities to operate on arrays of call arguments.

extension Array<LabeledExprSyntax> {
    /// Append a potentially labeled argument with the argument expression.
    mutating func append(label: String?, expression: ExprSyntax) {
        // Add a comma on the prior expression, if there is one.
        let leadingTrivia: Trivia
        if count > 0 {
            self[count - 1].trailingComma = TokenSyntax.commaToken()
            leadingTrivia = .newline

            // Adjust the first element to start with a newline
            if count == 1 {
                self[0].leadingTrivia = .newline
            }
        } else {
            leadingTrivia = Trivia()
        }

        // Add the new expression.
        append(
            LabeledExprSyntax(
                label: label,
                expression: expression
            ).with(\.leadingTrivia, leadingTrivia)
        )
    }

    /// Append a potentially labeled argument with a string literal.
    mutating func append(label: String?, stringLiteral: String) {
        append(label: label, expression: "\(literal: stringLiteral)")
    }

    /// Append a potentially labeled argument with a string literal, but only
    /// when the string literal is not nil.
    mutating func appendIf(label: String?, stringLiteral: String?) {
        if let stringLiteral {
            append(label: label, stringLiteral: stringLiteral)
        }
    }

    /// Append an array literal containing elements that can be rendered
    /// into expression syntax nodes.
    mutating func append<T>(
        label: String?,
        arrayLiteral: [T]
    ) where T: ManifestSyntaxRepresentable, T.PreferredSyntax == ExprSyntax {
        var elements: [ArrayElementSyntax] = []
        for element in arrayLiteral {
            elements.append(expression: element.asSyntax())
        }

        // Figure out the trivia for the left and right square
        let leftSquareTrailingTrivia: Trivia
        let rightSquareLeadingTrivia: Trivia
        switch elements.count {
        case 0:
            // Put a single space between the square brackets.
            leftSquareTrailingTrivia = Trivia()
            rightSquareLeadingTrivia = .space

        case 1:
            // Put spaces around the single element
            leftSquareTrailingTrivia = .space
            rightSquareLeadingTrivia = .space

        default:
            // Each of the elements will have a leading newline. Add a leading
            // newline before the close bracket.
            leftSquareTrailingTrivia = Trivia()
            rightSquareLeadingTrivia = .newline
        }

        let array = ArrayExprSyntax(
            leftSquare: .leftSquareToken(
                trailingTrivia: leftSquareTrailingTrivia
            ),
            elements: ArrayElementListSyntax(elements),
            rightSquare: .rightSquareToken(
                leadingTrivia: rightSquareLeadingTrivia
            )
        )
        append(label: label, expression: ExprSyntax(array))
    }

    /// Append an array literal containing elements that can be rendered
    /// into expression syntax nodes.
    mutating func appendIf<T>(
        label: String?,
        arrayLiteral: [T]?
    ) where T: ManifestSyntaxRepresentable, T.PreferredSyntax == ExprSyntax {
        guard let arrayLiteral else { return }
        append(label: label, arrayLiteral: arrayLiteral)
    }

    /// Append an array literal containing elements that can be rendered
    /// into expression syntax nodes, but only if it's not empty.
    mutating func appendIfNonEmpty<T>(
        label: String?,
        arrayLiteral: [T]
    ) where T: ManifestSyntaxRepresentable, T.PreferredSyntax == ExprSyntax {
        if arrayLiteral.isEmpty { return }

        append(label: label, arrayLiteral: arrayLiteral)
    }
}

// MARK: Utilities for adding arguments into calls.
fileprivate class ReplacingRewriter: SyntaxRewriter {
    let childNode: Syntax
    let newChildNode: Syntax

    init(childNode: Syntax, newChildNode: Syntax) {
        self.childNode = childNode
        self.newChildNode = newChildNode
        super.init()
    }

    override func visitAny(_ node: Syntax) -> Syntax? {
        if node == childNode {
            return newChildNode
        }

        return nil
    }
}

fileprivate extension SyntaxProtocol {
    /// Replace the given child with a new child node.
    func replacingChild(_ childNode: Syntax, with newChildNode: Syntax) -> Self {
        return ReplacingRewriter(
            childNode: childNode,
            newChildNode: newChildNode
        ).rewrite(self).cast(Self.self)
    }
}

extension FunctionCallExprSyntax {
    /// Produce source edits that will add the given new element to the
    /// array for an argument with the given label (if there is one), or
    /// introduce a new argument with an array literal containing only the
    /// new element.
    ///
    /// - Parameters:
    ///   - label: The argument label for the argument whose array will be
    ///     added or modified.
    ///   - trailingLabels: The argument labels that could follow the label,
    ///     which helps determine where the argument should be inserted if
    ///     it doesn't exist yet.
    ///   - newElement: The new element.
    /// - Returns: the function call after making this change.
    func appendingToArrayArgument(
        label: String,
        trailingLabels: Set<String>,
        newElement: ExprSyntax
    ) throws -> FunctionCallExprSyntax {
        // If there is already an argument with this name, append to the array
        // literal in there.
        if let arg = findArgument(labeled: label) {
            guard let argArray = arg.expression.findArrayArgument() else {
                throw ManifestEditError.cannotFindArrayLiteralArgument(
                    argumentName: label,
                    node: Syntax(arg.expression)
                )
            }

            // Format the element appropriately for the context.
            let indentation = Trivia(
                pieces: arg.leadingTrivia.filter { $0.isSpaceOrTab }
            )
            let format = BasicFormat(
                indentationWidth: [ defaultIndent ],
                initialIndentation: indentation.appending(defaultIndent)
            )
            let formattedElement = newElement.formatted(using: format)
                .cast(ExprSyntax.self)

            let updatedArgArray = argArray.appending(
                element: formattedElement,
                outerLeadingTrivia: arg.leadingTrivia
            )

            return replacingChild(Syntax(argArray), with: Syntax(updatedArgArray))
        }

        // There was no argument, so we need to create one.

        // Insert the new argument at the appropriate place in the call.
        let insertionPos = arguments.findArgumentInsertionPosition(
            labelsAfter: trailingLabels
        )
        let newArguments = arguments.insertingArgument(
            at: insertionPos
        ) { (leadingTrivia, trailingComma) in
            // Format the element appropriately for the context.
            let indentation = Trivia(pieces: leadingTrivia.filter { $0.isSpaceOrTab })
            let format = BasicFormat(
                indentationWidth: [ defaultIndent ],
                initialIndentation: indentation.appending(defaultIndent)
            )
            let formattedElement = newElement.formatted(using: format)
                .cast(ExprSyntax.self)

            // Form the array.
            let newArgument = ArrayExprSyntax(
                leadingTrivia: .space,
                leftSquare: .leftSquareToken(
                    trailingTrivia: .newline
                ),
                elements: ArrayElementListSyntax(
                    [
                        ArrayElementSyntax(
                            expression: formattedElement,
                            trailingComma: .commaToken()
                        )
                    ]
                ),
                rightSquare: .rightSquareToken(
                    leadingTrivia: leadingTrivia
                )
            )

            // Create the labeled argument for the array.
            return LabeledExprSyntax(
                leadingTrivia: leadingTrivia,
                label: "\(raw: label)",
                colon: .colonToken(),
                expression: ExprSyntax(newArgument),
                trailingComma: trailingComma
            )
        }

        return with(\.arguments, newArguments)
    }
}
