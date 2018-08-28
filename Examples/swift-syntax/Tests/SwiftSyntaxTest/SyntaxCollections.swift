import XCTest
import SwiftSyntax

fileprivate func integerLiteralElement(_ int: Int) -> ArrayElementSyntax {
    let literal = SyntaxFactory.makeIntegerLiteral("\(int)")
    return SyntaxFactory.makeArrayElement(
        expression: SyntaxFactory.makeIntegerLiteralExpr(digits: literal),
        trailingComma: nil)
}

public class SyntaxCollectionsAPITestCase: XCTestCase {
  public func testAppendingElement() {
      let arrayElementList = SyntaxFactory.makeArrayElementList([
          integerLiteralElement(0)
      ])

      let newArrayElementList = arrayElementList.appending(integerLiteralElement(1))

      XCTAssertEqual(newArrayElementList.count, 2)
      XCTAssertNotNil(newArrayElementList.child(at: 1))
      XCTAssertEqual("\(newArrayElementList.child(at: 1)!)", "1")
  }

  public func testInsertingElement() {
      let arrayElementList = SyntaxFactory.makeArrayElementList([
          integerLiteralElement(1)
      ])

      var newArrayElementList = arrayElementList.inserting(integerLiteralElement(0), at: 0)

      XCTAssertEqual(newArrayElementList.count, 2)
      XCTAssertNotNil(newArrayElementList.child(at: 0))
      XCTAssertEqual("\(newArrayElementList.child(at: 0)!)", "0")

      newArrayElementList = newArrayElementList.inserting(integerLiteralElement(2), at: 2)

      XCTAssertEqual(newArrayElementList.count, 3)
      XCTAssertNotNil(newArrayElementList.child(at: 2))
      XCTAssertEqual("\(newArrayElementList.child(at: 2)!)", "2")
  }

  public func testPrependingElement() {
      let arrayElementList = SyntaxFactory.makeArrayElementList([
          integerLiteralElement(1)
      ])

      let newArrayElementList = arrayElementList.prepending(integerLiteralElement(0))

      XCTAssertEqual(newArrayElementList.count, 2)
      XCTAssertNotNil(newArrayElementList.child(at: 0))
      XCTAssertEqual("\(newArrayElementList.child(at: 0)!)", "0")
  }

  public func testRemovingFirstElement() {
      let arrayElementList = SyntaxFactory.makeArrayElementList([
          integerLiteralElement(0),
          integerLiteralElement(1)
      ])

      let newArrayElementList = arrayElementList.removingFirst()

      XCTAssertEqual(newArrayElementList.count, 1)
      XCTAssertNotNil(newArrayElementList.child(at: 0))
      XCTAssertEqual("\(newArrayElementList.child(at: 0)!)", "1")
  }

  public func testRemovingLastElement() {
      let arrayElementList = SyntaxFactory.makeArrayElementList([
          integerLiteralElement(0),
          integerLiteralElement(1)
      ])

      let newArrayElementList = arrayElementList.removingLast()

      XCTAssertEqual(newArrayElementList.count, 1)
      XCTAssertNotNil(newArrayElementList.child(at: 0))
      XCTAssertEqual("\(newArrayElementList.child(at: 0)!)", "0")
  }

  public func testRemovingElement() {
      let arrayElementList = SyntaxFactory.makeArrayElementList([
          integerLiteralElement(0)
      ])

      let newArrayElementList = arrayElementList.removing(childAt: 0)

      XCTAssertEqual(newArrayElementList.count, 0)
      XCTAssertNil(newArrayElementList.child(at: 0))
  }

  public func testReplacingElement() {
      let arrayElementList = SyntaxFactory.makeArrayElementList([
          integerLiteralElement(0),
          integerLiteralElement(1),
          integerLiteralElement(2)
      ])

      let newArrayElementList = arrayElementList.replacing(childAt: 2,
                                                           with: integerLiteralElement(3))

      XCTAssertNotNil(newArrayElementList.child(at: 2))
      XCTAssertEqual("\(newArrayElementList.child(at: 2)!)", "3")
  }
}
