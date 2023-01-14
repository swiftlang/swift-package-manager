#import <XCTest/XCTest.h>

// IMPORTANT: The generated "bridging" header must be imported before the
// generated interop header.
#import "MixedTargetWithCustomModuleMap/MixedTargetWithCustomModuleMap.h"
#import "MixedTargetWithCustomModuleMap-Swift.h"

@interface ObjcMixedTargetWithCustomModuleMapTestsViaGeneratedBridgingHeader : XCTestCase
@end

@implementation ObjcMixedTargetWithCustomModuleMapTestsViaGeneratedBridgingHeader

- (void)testPublicSwiftAPI {
    // Check that Objective-C compatible Swift API surface is exposed...
    Engine *engine = [[Engine alloc] init];
}

- (void)testPublicObjcAPI {
    // Check that Objective-C API surface is exposed...
    MyMachine *machine = [[MyMachine alloc] init];
    MyOldCar *oldCar = [[MyOldCar alloc] init];
    MyDriver *driver = [[MyDriver alloc] init];
}

@end
