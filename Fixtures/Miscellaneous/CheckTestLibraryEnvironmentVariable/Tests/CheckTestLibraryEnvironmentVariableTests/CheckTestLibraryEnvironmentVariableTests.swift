import XCTest

final class CheckTestLibraryEnvironmentVariableTests: XCTestCase {
    func testEnvironmentVariable() throws {
        let envvar = ProcessInfo.processInfo.environment["SWIFT_PM_TEST_LIBRARY"]
        XCTAssertEqual(envvar, "XCTest")
    }
}
