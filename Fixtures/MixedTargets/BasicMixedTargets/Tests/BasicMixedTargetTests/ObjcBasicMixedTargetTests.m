#import <XCTest/XCTest.h>

@import BasicMixedTarget;

@interface ObjcBasicMixedTargetTests : XCTestCase

@end

@implementation ObjcBasicMixedTargetTests

- (void)testPublicSwiftAPI {
    // Check that Objective-C compatible Swift API surface is exposed...
    Engine *engine = [[Engine alloc] init];
}

- (void)testPublicObjcAPI {
    // Check that Objective-C API surface is exposed...
    OldCar *oldCar = [[OldCar alloc] init];
    Driver *driver = [[Driver alloc] init];
}

@end
