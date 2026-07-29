import XCTest

import PluginConsumer

final class MinimalWebAssemblyPluginPackageTests: XCTestCase {
    func testGeneratedSource() {
        XCTAssertEqual(pluginConsumerValue(), "generated")
    }
}
