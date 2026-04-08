import XCTest

final class FailingSuite1: XCTestCase {
    func testFailing() {
        XCTAssertTrue(false, "Intentional failure in FailingSuite1")
    }
}

final class FailingSuite2: XCTestCase {
    func testFailing() {
        XCTAssertTrue(false, "Intentional failure in FailingSuite2")
    }
}

final class PassingSuite1: XCTestCase {
    func testPassing() {
        XCTAssertTrue(true)
    }
}

final class PassingSuite2: XCTestCase {
    func testPassing() {
        XCTAssertTrue(true)
    }
}
