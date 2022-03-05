import XCTest
import MyLibrary

final class MyLibraryTests: XCTestCase {
    
    func testLibrary() throws {
        XCTAssertEqual(Foo(), "Foo")
    }
}
