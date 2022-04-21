import XCTest
@testable import ParallelTestsPkg

class ParallelTestsSkippedTests: XCTestCase {

    func testSureSkipped() throws {
        try XCTSkipIf(true)
    }
}
