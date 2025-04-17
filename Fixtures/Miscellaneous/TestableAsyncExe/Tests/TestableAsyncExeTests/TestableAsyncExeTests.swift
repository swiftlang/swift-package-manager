import XCTest
@testable import TestableAsyncExe1
@testable import TestableAsyncExe2
@testable import TestableAsyncExe3
@testable import TestableAsyncExe4

final class TestableAsyncExeTests: XCTestCase {
    func testExample() async throws {
        let greeting1 = await GetAsyncGreeting1()
        print(greeting1)
        XCTAssertEqual(greeting1, "Hello, async world")

        let greeting2 = await GetAsyncGreeting2()
        print(greeting2)
        XCTAssertEqual(greeting2, "Hello, async planet")

        let greeting3 = await AsyncMain3.getGreeting3()
        print(greeting3)
        XCTAssertEqual(greeting3, "Hello, async galaxy")

        let greeting4 = await AsyncMain4.getGreeting4()
        print(greeting4)
        XCTAssertEqual(greeting4, "Hello, async universe")
    }
}
