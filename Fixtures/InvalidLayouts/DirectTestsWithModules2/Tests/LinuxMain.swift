import XCTest

@testable import DirectTests
@testable import DirectTestsWithModules2

XCTMain([
    FooTests(),
    BarTests(),
])

