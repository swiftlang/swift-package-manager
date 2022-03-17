import XCTest
import MyLibrary

final class MyLibraryTests: XCTestCase {
    
    func testLibrary() throws {
        XCTAssertEqual(GetGeneratedString(), "Generated string: 4920616d20466f6f210a")
    }
}
