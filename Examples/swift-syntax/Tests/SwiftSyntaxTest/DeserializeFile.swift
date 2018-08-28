import XCTest
import SwiftSyntax

public class DecodeSytnaxTestCase: XCTestCase {
  public func testBasic() {
    XCTAssertNoThrow(try {
      let inputFile = getInput("visitor.swift")
      let source = try String(contentsOf: inputFile)
      let parsed = try SyntaxTreeParser.parse(inputFile)
      XCTAssertEqual("\(parsed)", source)
    }())
  }
}
