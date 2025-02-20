import SPMBuildCore
import XCTest

open class BuildSystemProviderTestCase: XCTestCase {
    open var buildSystemProvider: BuildSystemProvider.Kind {
        fatalError("\(self) does not implement \(#function)")
    }
}
