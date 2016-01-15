import XCTest
import XCTestCaseProvider
import func POSIX.popen

class DependencyResolutionTestCase: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () throws -> Void)] {
        return [
            ("testInternalSimple", testInternalSimple),
            ("testInternalComplex", testInternalComplex),
            ("testExternalSimple", testExternalSimple),
            ("testExternalComplex", testExternalComplex),
        ]
    }

    func testInternalSimple() {
        fixture(name: "DependencyResolution/Internal/Simple") { prefix in
            XCTAssertBuilds(prefix)

            let output = try popen(["\(prefix)/.build/debug/Foo"])
            XCTAssertEqual(output, "Foo\nBar\n")
        }
    }

    func testInternalComplex() {
        fixture(name: "DependencyResolution/Internal/Complex") { prefix in
            XCTAssertBuilds(prefix)

            let output = try popen(["\(prefix)/.build/debug/Foo"])
            XCTAssertEqual(output, "meiow Baz\n")
        }
    }

    func testExternalSimple() {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            XCTAssertBuilds(prefix, "Bar")
            XCTAssertFileExists(prefix, "Bar/.build/debug/Bar")
            XCTAssertDirectoryExists(prefix, "Bar/Packages/Foo-1.2.3")
        }
    }

    func testExternalComplex() {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            XCTAssertBuilds(prefix, "app")
            let output = try POSIX.popen(["\(prefix)/app/.build/debug/Dealer"])
            XCTAssertEqual(output, "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
        }
    }
}
