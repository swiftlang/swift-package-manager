import XCTest
@testable import ParallelTestsPkg

class ParallelTestsFailureTests: XCTestCase {

    func testSureFailure() {
        XCTFail("Giving up is the only sure way to fail.")
    }

    func testAssertionFailure() {
        XCTAssertTrue(false, "Expected assertion failure.")
    }

    func testExpectationFailure() {
        let expectation = XCTestExpectation(description: "failing expectation")
        wait(for: [expectation], timeout: 0.0)
    }
}
