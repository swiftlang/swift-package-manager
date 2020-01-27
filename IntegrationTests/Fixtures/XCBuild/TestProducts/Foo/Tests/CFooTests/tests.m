@import XCTest;
@import Foundation;
@import FooLib;
@import BarLib;

@interface CFooTests: XCTestCase
@end
@implementation CFooTests

- (void)testFoo {
    XCTAssertEqual([FooInfo name], @"Foo");
}

- (void)testBar {
    XCTAssertEqual([BarInfo name], @"Bar");
}

@end