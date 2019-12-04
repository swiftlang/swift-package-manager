import XCTest
import lib

final class libTests: XCTestCase {
    func testDoubleFree() {
        executeDoubleFree()
    }
}
