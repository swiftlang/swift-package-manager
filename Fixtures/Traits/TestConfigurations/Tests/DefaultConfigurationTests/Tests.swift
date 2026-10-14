import Library
import XCTest

final class DefaultConfigurationTests: XCTestCase {
    func testDefaultTraitsAreActive() {
        XCTAssertEqual(Library.enabledTraits, ["Foo"])
    }
}
