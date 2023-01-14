#import <XCTest/XCTest.h>

// IMPORTANT: The generated "bridging" header must be imported before the
// generated interop header.
#import "BasicMixedTarget/BasicMixedTarget.h"
#import "BasicMixedTarget-Swift.h"

@interface ObjcBasicMixedTargetTestsViaGeneratedBridgingHeader : XCTestCase

@end

@implementation ObjcBasicMixedTargetTestsViaGeneratedBridgingHeader

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
