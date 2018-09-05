import XCTest
import SwiftSyntax

public class SyntaxVisitorTestCase: XCTestCase {
  public func testBasic() {
    class FuncCounter: SyntaxVisitor {
      var funcCount = 0
      override func visit(_ node: FunctionDeclSyntax) {
        funcCount += 1
        super.visit(node)
      }
    }
    XCTAssertNoThrow(try {
      let parsed = try SyntaxTreeParser.parse(getInput("visitor.swift"))
      let counter = FuncCounter()
      let hashBefore = parsed.hashValue
      counter.visit(parsed)
      XCTAssertEqual(counter.funcCount, 3)
      XCTAssertEqual(hashBefore, parsed.hashValue)
    }())
  }

  public func testRewritingNodeWithEmptyChild() {
    class ClosureRewriter: SyntaxRewriter {
      override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
        // Perform a no-op transform that requires rebuilding the node.
        return node.withSignature(node.signature)
      }
    }
    XCTAssertNoThrow(try {
      let parsed = try SyntaxTreeParser.parse(getInput("closure.swift"))
      let rewriter = ClosureRewriter()
      let rewritten = rewriter.visit(parsed)
      XCTAssertEqual(parsed.description, rewritten.description)
    }())
  }

  public func testSyntaxRewriterVisitAny() {
    class VisitAnyRewriter: SyntaxRewriter {
      let transform: (TokenSyntax) -> TokenSyntax
      init(transform: @escaping (TokenSyntax) -> TokenSyntax) {
        self.transform = transform
      }
      override func visitAny(_ node: Syntax) -> Syntax? {
        if let tok = node as? TokenSyntax {
          return transform(tok)
        }
        return nil
      }
    }
    XCTAssertNoThrow(try {
      let parsed = try SyntaxTreeParser.parse(getInput("near-empty.swift"))
      let rewriter = VisitAnyRewriter(transform: { _ in
         return SyntaxFactory.makeIdentifier("")
      })
      let rewritten = rewriter.visit(parsed)
      XCTAssertEqual(rewritten.description, "")
    }())
  }

  public func testSyntaxRewriterVisitCollection() {
    class VisitCollections: SyntaxVisitor {
      var numberOfCodeBlockItems = 0

      override func visit(_ items: CodeBlockItemListSyntax) {
        numberOfCodeBlockItems += items.count
        super.visit(items)
      }
    }

    XCTAssertNoThrow(try {
      let parsed = try SyntaxTreeParser.parse(getInput("nested-blocks.swift"))
      let visitor = VisitCollections()
      visitor.visit(parsed)
      XCTAssertEqual(4, visitor.numberOfCodeBlockItems)
    }())
  }
}
