import XCTest
import BasicMixedTargetWithNestedUmbrellaHeader

final class BasicMixedTargetWithNestedUmbrellaHeaderTests: XCTestCase {

    func testPublicSwiftAPI() throws {
        // Check that Swift API surface is exposed...
        let _ = NewPlane()
        let _ = Engine()
    }

    func testPublicObjcAPI() throws {
        // Check that Objective-C API surface is exposed...
        let _ = OldPlane()
        let _ = Pilot()
    }

    func testModulePrefixingWorks() throws {
        let _ = BasicMixedTargetWithNestedUmbrellaHeader.NewPlane()
        let _ = BasicMixedTargetWithNestedUmbrellaHeader.Engine()
        let _ = BasicMixedTargetWithNestedUmbrellaHeader.OldPlane()
        let _ = BasicMixedTargetWithNestedUmbrellaHeader.Pilot()
    }

}
