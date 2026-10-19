import Library
import XCTest

final class AllTraitsConfigurationTests: XCTestCase {
    func testAllTraitsAreActive() {
        XCTAssertEqual(Library.enabledTraits, ["Foo", "Bar"])
    }

    // This target references API that only exists when the `Bar` trait is
    // enabled, so it only compiles under its declared configuration. If the
    // matrix built this target during the default-configuration run, the whole
    // run would fail to build.
    func testBarOnlyAPIIsAvailable() {
        XCTAssertEqual(Library.barOnlyAPI(), "bar")
    }
}
