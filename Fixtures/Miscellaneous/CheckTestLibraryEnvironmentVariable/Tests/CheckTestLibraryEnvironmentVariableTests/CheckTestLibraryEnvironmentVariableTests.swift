import XCTest

final class CheckTestLibraryEnvironmentVariableTests: XCTestCase {
    func testEnvironmentVariables() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "Test is macOS specific")
        #endif

        let testingEnabled = ProcessInfo.processInfo.environment["SWIFT_TESTING_ENABLED"]
        XCTAssertEqual(testingEnabled, "0")

        if ProcessInfo.processInfo.environment["CONTAINS_SWIFT_TESTING"] != nil {
            let frameworkPath = try XCTUnwrap(ProcessInfo.processInfo.environment["DYLD_FRAMEWORK_PATH"])
            let libraryPath = try XCTUnwrap(ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"])
            XCTAssertTrue(
                frameworkPath.contains("testing") || libraryPath.contains("testing"),
                "Expected 'testing' in '\(frameworkPath)' or '\(libraryPath)'"
            )
        }
    }
}
