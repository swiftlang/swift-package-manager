#import <XCTest/XCTest.h>

#import "BasicMixedTarget-Swift.h"
#import "BasicMixedTarget/BasicMixedTarget.h"

@interface ObjcBasicMixedTargetTestsViaBridgingHeader : XCTestCase

@end

@implementation ObjcBasicMixedTargetTestsViaBridgingHeader

- (void)testPublicSwiftAPI {
    // Check that Objective-C compatible Swift API surface is exposed...
    Engine *engine = [[Engine alloc] init];
}

- (void)testPublicObjcAPI {
    // Check that Objective-C API surface is exposed...
    OldCar *oldCar = [[OldCar alloc] init];
    Driver *driver = [[Driver alloc] init];
    CarPart *carPart = [[CarPart alloc] init];
}

@end
