import XCTest

@testable import DirectTestsWithModules1
@testable import ModuleAtest

XCTMain([
    FooTests(),
    BarTests(),
])

