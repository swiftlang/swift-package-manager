import Testing
import XCTest

import Simple


final public class XCTesting: XCTestCase {
    func testGreetWithEmptyArgument() {
        let actual = greet()
        XCTAssertEqual(actual, "Hello, World!")
    }

    func testGreetWithNonEmptyArgument() {
        let name = "MyName"
        let person = Person(name: name)
        let actual = greet(person: person)
        XCTAssertEqual(actual, "Hello, \(name)!")
    }
}

@Suite
struct STTestTests {
    @Test("STTest tests")
    func testGreetWithEmptyArgument() {
        let actual = greet()
        #expect(actual == "Hello, World!")
    }

    @Test("STTest tests")
    func testGreetWithNonEmptyArgument() {
        let name = "MyName"
        let person = Person(name: name)
        let actual = greet(person: person)
        #expect(actual == "Hello, \(name)!")
    }
}
