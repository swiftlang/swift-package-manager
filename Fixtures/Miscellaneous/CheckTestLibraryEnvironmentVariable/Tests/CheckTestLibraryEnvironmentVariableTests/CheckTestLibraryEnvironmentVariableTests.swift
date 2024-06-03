import XCTest

final class CheckTestLibraryEnvironmentVariableTests: XCTestCase {
    func testEnviromentVariable() throws {
        let envvar = ProcessInfo.processInfo.environment["SWIFT_PM_TEST_LIBRARY"]
        XCTAssertEqual(envvar, "XCTest")
    }
}
