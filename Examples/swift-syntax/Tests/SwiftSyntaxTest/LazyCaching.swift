import XCTest
import SwiftSyntax

class LazyCachingTestCase: XCTestCase {
  public func testPathological() {
    let tuple = SyntaxFactory.makeVoidTupleType()

    DispatchQueue.concurrentPerform(iterations: 100) { _ in
      XCTAssertEqual(tuple.leftParen, tuple.leftParen)
    }
  }

  public func testTwoAccesses() {
    let tuple = SyntaxFactory.makeVoidTupleType()

    let queue1 = DispatchQueue(label: "queue1")
    let queue2 = DispatchQueue(label: "queue2")

    var node1: TokenSyntax?
    var node2: TokenSyntax?

    let group = DispatchGroup()
    queue1.async(group: group) {
      node1 = tuple.leftParen
    }
    queue2.async(group: group) {
      node2 = tuple.leftParen
    }
    group.wait()

    let final = tuple.leftParen

    XCTAssertNotNil(node1)
    XCTAssertNotNil(node2)
    XCTAssertEqual(node1, node2)
    XCTAssertEqual(node1, final)
    XCTAssertEqual(node2, final)
  }

}
