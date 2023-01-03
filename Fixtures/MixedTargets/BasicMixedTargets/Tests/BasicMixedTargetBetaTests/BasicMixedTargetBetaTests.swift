import XCTest
import BasicMixedTargetBeta

final class BasicMixedTargetBetaTests: XCTestCase {

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
        let _ = BasicMixedTargetBeta.NewPlane()
        let _ = BasicMixedTargetBeta.Engine()
        let _ = BasicMixedTargetBeta.OldPlane()
        let _ = BasicMixedTargetBeta.Pilot()
    }

}
