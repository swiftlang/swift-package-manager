import XCTest
import BasicMixedTargetWithManualBridgingHeader

final class BasicMixedTargetWithManualBridgingHeaderTests: XCTestCase {

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
        let _ = BasicMixedTargetWithManualBridgingHeader.NewPlane()
        let _ = BasicMixedTargetWithManualBridgingHeader.Engine()
        let _ = BasicMixedTargetWithManualBridgingHeader.OldPlane()
        let _ = BasicMixedTargetWithManualBridgingHeader.Pilot()
    }

}
