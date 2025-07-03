import XCTest
import FooLib
import BarLib

final class FooTests: XCTestCase {
    func testFoo() {
        XCTAssertEqual(FooInfo.name, "Foo")
    }

    func testBar() {
        XCTAssertEqual(BarInfo.name(), "Bar")
    }
}