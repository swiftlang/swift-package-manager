import XCTest
import MixedTargetWithNonPublicHeaders

#if EXPECT_FAILURE

final class MixedTargetWithCTests: XCTestCase {
    func testInternalObjcTypesAreNotExposed() throws {
        // The following Objective-C types are defined in non-public headers
        // within the `MixedTargetWithNonPublicHeaders` target. They should not be
        // visible in this context and should cause a failure when building the
        // test target associated with this file.
        let _  = Foo()
        let _ = Bar()
    }
}

#endif  // EXPECT_FAILURE
