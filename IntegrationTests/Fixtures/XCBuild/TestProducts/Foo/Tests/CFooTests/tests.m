@import XCTest;
@import Foundation;
@import FooLib;
@import BarLib;

@interface CFooTests: XCTestCase
@end
@implementation CFooTests

- (void)testFoo {
    XCTAssert([[FooInfo name] isEqualTo:@"Foo"]);
}

- (void)testBar {
    XCTAssert([[BarInfo name] isEqualTo:@"Bar"]);
}

@end
