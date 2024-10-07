import XCTest

final class CheckTestLibraryEnvironmentVariableTests: XCTestCase {
    func testEnviromentVariable() throws {
        let envvar = ProcessInfo.processInfo.environment["SWIFT_TESTING_ENABLED"]
        XCTAssertEqual(envvar, "0")
    }
}
