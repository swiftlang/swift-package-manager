import XCTest
import Foundation
import AwesomeResources

final class MyTests: XCTestCase {
    func testFoo() {
        XCTAssertTrue(AwesomeResource().hello == "hello")
    }
    func testBar() {
        let world = try! String(contentsOf: Bundle.module.url(forResource: "world", withExtension: "txt")!)
        XCTAssertTrue(world == "world")
    }
}
