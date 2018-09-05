import XCTest
import SwiftSyntax

fileprivate func cannedStructDecl() -> StructDeclSyntax {
  let structKW = SyntaxFactory.makeStructKeyword(trailingTrivia: .spaces(1))
  let fooID = SyntaxFactory.makeIdentifier("Foo", trailingTrivia: .spaces(1))
  let rBrace = SyntaxFactory.makeRightBraceToken(leadingTrivia: .newlines(1))
  let members = MemberDeclBlockSyntax {
    $0.useLeftBrace(SyntaxFactory.makeLeftBraceToken())
    $0.useRightBrace(rBrace)
  }
  return StructDeclSyntax {
    $0.useStructKeyword(structKW)
    $0.useIdentifier(fooID)
    $0.useMembers(members)
  }
}

public class SyntaxFactoryAPITestCase: XCTestCase {
  public func testGenerated() {

    let structDecl = cannedStructDecl()

    XCTAssertEqual("\(structDecl)",
                   """
                   struct Foo {
                   }
                   """)

    let forType = SyntaxFactory.makeIdentifier("for",
                                               leadingTrivia: .backticks(1),
                                               trailingTrivia: [
                                                 .backticks(1), .spaces(1)
                                               ])
    let newBrace = SyntaxFactory.makeRightBraceToken(leadingTrivia: .newlines(2))

    let renamed = structDecl.withIdentifier(forType)
                            .withMembers(structDecl.members
                                                   .withRightBrace(newBrace))

    XCTAssertEqual("\(renamed)",
                   """
                   struct `for` {

                   }
                   """)

    XCTAssertNotEqual(structDecl.members, renamed.members)
    XCTAssertEqual(structDecl, structDecl.root as? StructDeclSyntax)
    XCTAssertNil(structDecl.parent)
    XCTAssertNotNil(structDecl.members.parent)
    XCTAssertEqual(structDecl.members.parent as? StructDeclSyntax, structDecl)

    // Ensure that accessing children via named identifiers is exactly the
    // same as accessing them as their underlying data.
    XCTAssertEqual(structDecl.members,
                structDecl.child(at: 7) as? MemberDeclBlockSyntax)

    XCTAssertEqual("\(structDecl.members.rightBrace)",
                   """

                   }
                   """)
  }

  public func testTokenSyntax() {
    let tok = SyntaxFactory.makeStructKeyword()
    XCTAssertEqual("\(tok)", "struct")
    XCTAssertTrue(tok.isPresent)

    let preSpacedTok = tok.withLeadingTrivia(.spaces(3))
    XCTAssertEqual("\(preSpacedTok)", "   struct")

    let postSpacedTok = tok.withTrailingTrivia(.spaces(6))
    XCTAssertEqual("\(postSpacedTok)", "struct      ")

    let prePostSpacedTok = preSpacedTok.withTrailingTrivia(.spaces(4))
    XCTAssertEqual("\(prePostSpacedTok)", "   struct    ")
  }

  public func testFunctionCallSyntaxBuilder() {
    let string = SyntaxFactory.makeStringLiteralExpr("Hello, world!")
    let printID = SyntaxFactory.makeVariableExpr("print")
    let arg = FunctionCallArgumentSyntax {
      $0.useExpression(string)
    }
    let call = FunctionCallExprSyntax {
      $0.useCalledExpression(printID)
      $0.useLeftParen(SyntaxFactory.makeLeftParenToken())
      $0.addFunctionCallArgument(arg)
      $0.useRightParen(SyntaxFactory.makeRightParenToken())
    }
    XCTAssertEqual("\(call)", "print(\"Hello, world!\")")

    let terminatorArg = FunctionCallArgumentSyntax {
      $0.useLabel(SyntaxFactory.makeIdentifier("terminator"))
      $0.useColon(SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)))
      $0.useExpression(SyntaxFactory.makeStringLiteralExpr(" "))
    }
    let callWithTerminator = call.withArgumentList(
      SyntaxFactory.makeFunctionCallArgumentList([
        arg.withTrailingComma(
          SyntaxFactory.makeCommaToken(trailingTrivia: .spaces(1))),
        terminatorArg
      ])
    )

    XCTAssertEqual("\(callWithTerminator)",
                   "print(\"Hello, world!\", terminator: \" \")")
  }
}
