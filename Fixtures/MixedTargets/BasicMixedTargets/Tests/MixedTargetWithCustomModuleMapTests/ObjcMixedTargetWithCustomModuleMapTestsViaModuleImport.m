#import <XCTest/XCTest.h>

@import MixedTargetWithCustomModuleMap;

@interface ObjcMixedTargetWithCustomModuleMapTestsViaModuleImport : XCTestCase
@end

@implementation ObjcMixedTargetWithCustomModuleMapTestsViaModuleImport

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
