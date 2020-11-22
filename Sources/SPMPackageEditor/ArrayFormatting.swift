import SwiftSyntax

extension ArrayExprSyntax {
    public func withAdditionalElementExpr(_ expr: ExprSyntax) -> ArrayExprSyntax {
        if self.elements.count >= 2 {
            // If the array expression has >=2 elements, use the trivia between
            // the last and second-to-last elements to determine how we insert
            // the new one.
            let lastElement = self.elements.last!
            let secondToLastElement = self.elements[self.elements.index(self.elements.endIndex, offsetBy: -2)]

            let newElements = self.elements
                .removingLast()
                .appending(
                    lastElement.withTrailingComma(
                        SyntaxFactory.makeCommaToken(
                            trailingTrivia: (lastElement.trailingTrivia ?? []) +
                                rightSquare.leadingTrivia.droppingPiecesAfterLastComment() +
                                (secondToLastElement.trailingTrivia ?? [])
                        )
                    )
                )
                .appending(
                    SyntaxFactory.makeArrayElement(
                        expression: expr,
                        trailingComma: SyntaxFactory.makeCommaToken()
                    ).withLeadingTrivia(lastElement.leadingTrivia?.droppingPiecesUpToAndIncludingLastComment() ?? [])
                )

            return self.withElements(newElements)
                .withRightSquare(
                    self.rightSquare.withLeadingTrivia(
                        self.rightSquare.leadingTrivia.droppingPiecesUpToAndIncludingLastComment()
                    )
                )
        } else {
            // For empty and single-element array exprs, we determine the indent
            // of the line the opening square bracket appears on, and then use
            // that to indent the added element and closing brace onto newlines.
            var calculatedIndentTrivia: Trivia? = nil
            let sfSyntax = self.root.as(SourceFileSyntax.self)!
            let locationConverter = SourceLocationConverter(file: "", tree: sfSyntax)
            if let lineNumber = self.leftSquare.startLocation(converter: locationConverter).line {
                let indentVisitor = DetermineLineIndentVisitor(lineNumber: lineNumber,
                                                               sourceLocationConverter: locationConverter)
                indentVisitor.walk(sfSyntax)
                calculatedIndentTrivia = indentVisitor.lineIndent
            }
            // If the indent couldn't be calculated for some reason, fallback to 4 spaces.
            let indentTrivia = calculatedIndentTrivia ?? .spaces(4)

            let elementAdditionalIndentTrivia: Trivia
            if indentTrivia.allSatisfy(\.isSpaces) {
                let addedSpaces = indentTrivia.reduce(0, {
                    guard case .spaces(let count) = $1 else { fatalError() }
                    return $0 + count
                }) % 4 == 0 ? 4 : 2
                elementAdditionalIndentTrivia = .spaces(addedSpaces)
                print("indent")
                print(sfSyntax.description)
                print(indentTrivia.reduce(0, {
                    guard case .spaces(let count) = $1 else { fatalError() }
                    return $0 + count
                }))
            } else if indentTrivia.allSatisfy(\.isTabs) {
                elementAdditionalIndentTrivia = .tabs(1)
            } else {
                // If we can't determine the indent, default to 4 spaces.
                elementAdditionalIndentTrivia = .spaces(4)
            }

            var newElements: [ArrayElementSyntax] = []
            if !self.elements.isEmpty {
                let existingElement = self.elements.first!
                newElements.append(
                    SyntaxFactory.makeArrayElement(expression: existingElement.expression,
                                                   trailingComma: SyntaxFactory.makeCommaToken())
                        .withLeadingTrivia(indentTrivia + elementAdditionalIndentTrivia)
                        .withTrailingTrivia((existingElement.trailingTrivia ?? []) + .newlines(1))
                )
            }

            newElements.append(
                SyntaxFactory.makeArrayElement(expression: expr, trailingComma: SyntaxFactory.makeCommaToken())
                    .withLeadingTrivia(indentTrivia + elementAdditionalIndentTrivia)
            )

            return self.withLeftSquare(self.leftSquare.withTrailingTrivia(.newlines(1)))
                .withElements(SyntaxFactory.makeArrayElementList(newElements))
                .withRightSquare(self.rightSquare.withLeadingTrivia(.newlines(1) + indentTrivia))
        }
    }
}

fileprivate extension TriviaPiece {
    var isComment: Bool {
        switch self {
        case .spaces, .tabs, .verticalTabs, .formfeeds, .newlines,
             .carriageReturns, .carriageReturnLineFeeds, .garbageText:
            return false
        case .lineComment, .blockComment, .docLineComment, .docBlockComment:
            return true
        }
    }

    var isHorizontalWhitespace: Bool {
        switch self {
        case .spaces, .tabs:
            return true
        default:
            return false
        }
    }

    var isSpaces: Bool {
        guard case .spaces = self else { return false }
        return true
    }

    var isTabs: Bool {
        guard case .tabs = self else { return false }
        return true
    }
}

fileprivate extension Trivia {
    func droppingPiecesAfterLastComment() -> Trivia {
        Trivia(pieces: .init(self.lazy.reversed().drop(while: { !$0.isComment }).reversed()))
    }

    func droppingPiecesUpToAndIncludingLastComment() -> Trivia {
        Trivia(pieces: .init(self.lazy.reversed().prefix(while: { !$0.isComment }).reversed()))
    }
}

public final class DetermineLineIndentVisitor: SyntaxVisitor {

    let lineNumber: Int
    let locationConverter: SourceLocationConverter
    private var bestMatch: TokenSyntax?

    public var lineIndent: Trivia? {
        guard let pieces = bestMatch?.leadingTrivia
                .lazy
                .reversed()
                .prefix(while: \.isHorizontalWhitespace)
                .reversed() else { return nil }
        return Trivia(pieces: Array(pieces))
    }

    public init(lineNumber: Int, sourceLocationConverter: SourceLocationConverter) {
        self.lineNumber = lineNumber
        self.locationConverter = sourceLocationConverter
    }

    public override func visit(_ tokenSyntax: TokenSyntax) -> SyntaxVisitorContinueKind {
        let range = tokenSyntax.sourceRange(converter: locationConverter,
                                               afterLeadingTrivia: false,
                                               afterTrailingTrivia: true)
        guard let startLine = range.start.line,
              let endLine = range.end.line,
              let startColumn = range.start.column,
              let endColumn = range.end.column else {
            return .skipChildren
        }

        if (startLine, startColumn) <= (lineNumber, 1),
           (lineNumber, 1) <= (endLine, endColumn) {
            bestMatch = tokenSyntax
            return .visitChildren
        } else {
            return .skipChildren
        }
    }
}
