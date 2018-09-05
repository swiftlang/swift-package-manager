import XCTest
import SwiftSyntax

public class SyntaxChildrenAPITestCase: XCTestCase {
  public func testIterateWithAllPresent() {
    let returnStmt = SyntaxFactory.makeReturnStmt(
      returnKeyword: SyntaxFactory.makeReturnKeyword(),
      expression: SyntaxFactory.makeBlankUnknownExpr())

    var iterator = returnStmt.children.makeIterator()
    XCTAssertNext(&iterator) { ($0 as? TokenSyntax)?.tokenKind == .returnKeyword }
    XCTAssertNext(&iterator) { $0 is ExprSyntax }
    XCTAssertNextIsNil(&iterator)
  }

  public func testIterateWithSomeMissing() {
    let returnStmt = SyntaxFactory.makeReturnStmt(
      returnKeyword: SyntaxFactory.makeReturnKeyword(),
      expression: nil)

    var iterator = returnStmt.children.makeIterator()
    XCTAssertNext(&iterator) { ($0 as? TokenSyntax)?.tokenKind == .returnKeyword }
    XCTAssertNextIsNil(&iterator)
  }

  public func testIterateWithAllMissing() {
    let returnStmt = SyntaxFactory.makeBlankReturnStmt()

    var iterator = returnStmt.children.makeIterator()
    XCTAssertNextIsNil(&iterator)
  }
}
