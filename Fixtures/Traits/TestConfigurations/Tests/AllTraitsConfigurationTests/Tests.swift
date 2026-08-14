import Library
import XCTest

final class AllTraitsConfigurationTests: XCTestCase {
    func testAllTraitsAreActive() {
        XCTAssertEqual(Library.enabledTraits, ["Foo", "Bar"])
    }
}
