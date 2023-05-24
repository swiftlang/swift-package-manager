#if os(Windows)
import CRT
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class aaaaTests: XCTestCase {
    func testExample() throws {
        while true {
            sleep(1)
        }
    }
}
