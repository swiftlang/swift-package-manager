#import <XCTest/XCTest.h>

@import MixedTargetWithNoPublicObjectiveCHeaders;

@interface ObjcMixedTargetWithNoPublicObjectiveCHeadersTests : XCTestCase

@end

@implementation ObjcMixedTargetWithNoPublicObjectiveCHeadersTests

- (void)testPublicSwiftAPI {
    // Check that Objective-C compatible Swift API surface is exposed...
    Engine *engine = [[Engine alloc] init];
}

#if EXPECT_FAILURE
- (void)testObjcAPI {
    // No Objective-C API surface should be exposed...
    OldCar *oldCar = [[OldCar alloc] init];
    Driver *driver = [[Driver alloc] init];
}
#endif

@end
