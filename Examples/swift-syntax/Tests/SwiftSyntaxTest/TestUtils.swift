import Foundation
import SwiftSyntax
import XCTest

func getInput(_ file: String) -> URL {
  var result = URL(fileURLWithPath: #file)
  result.deleteLastPathComponent()
  result.appendPathComponent("Inputs")
  result.appendPathComponent(file)
  return result
}

/// Verifies that there is a next item returned by the iterator and that it
/// satisfies the given predicate.
func XCTAssertNext<Iterator: IteratorProtocol>(
  _ iterator: inout Iterator,
  satisfies predicate: (Iterator.Element) throws -> Bool
  ) rethrows {
  let next = iterator.next()
  XCTAssertNotNil(next)
  XCTAssertTrue(try predicate(next!))
}

/// Verifies that the iterator is exhausted.
func XCTAssertNextIsNil<Iterator: IteratorProtocol>(_ iterator: inout Iterator) {
  XCTAssertNil(iterator.next())
}
