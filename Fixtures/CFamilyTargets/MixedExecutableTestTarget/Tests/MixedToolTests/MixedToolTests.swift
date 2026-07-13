import XCTest
@testable import MixedTool

final class MixedToolTests: XCTestCase {
    func testSwiftAPI() {

        XCTAssertEqual(toolSwiftValue(), 10)
    }

    func testClangAPI() {

        XCTAssertEqual(tool_c_value(), 20)
    }
}
