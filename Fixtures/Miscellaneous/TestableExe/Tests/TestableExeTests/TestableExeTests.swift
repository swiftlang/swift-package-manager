import XCTest
@testable import TestableExe1
@testable import TestableExe2
// import TestableExe3
import class Foundation.Bundle

final class TestableExeTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.

        print(GetGreeting1())
        XCTAssertEqual(GetGreeting1(), "Hello, world")
        print(GetGreeting2())
        XCTAssertEqual(GetGreeting2(), "Hello, planet")
        // XCTAssertEqual(String(cString: GetGreeting3()), "Hello, universe")

        // Some of the APIs that we use below are available in macOS 10.13 and above.
        guard #available(macOS 10.13, *) else {
            return
        }

        var execPath = productsDirectory.appendingPathComponent("TestableExe1")
        var process = Process()
        process.executableURL = execPath
        var pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        var data = pipe.fileHandleForReading.readDataToEndOfFile()
        var output = String(data: data, encoding: .utf8)
        XCTAssertEqual(output, "Hello, world!\n")

        execPath = productsDirectory.appendingPathComponent("TestableExe2")
        process = Process()
        process.executableURL = execPath
        pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        output = String(data: data, encoding: .utf8)
        XCTAssertEqual(output, "Hello, planet!\n")

        execPath = productsDirectory.appendingPathComponent("TestableExe3")
        process = Process()
        process.executableURL = execPath
        pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        output = String(data: data, encoding: .utf8)
        XCTAssertEqual(output, "Hello, universe!\n")
    }

    /// Returns path to the built products directory.
    var productsDirectory: URL {
      #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't find the products directory")
      #else
        return Bundle.main.bundleURL
      #endif
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
