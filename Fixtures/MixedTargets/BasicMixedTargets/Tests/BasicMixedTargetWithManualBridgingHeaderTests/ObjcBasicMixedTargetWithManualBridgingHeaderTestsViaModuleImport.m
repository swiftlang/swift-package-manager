#import <XCTest/XCTest.h>

// Import the target via a module import.
@import BasicMixedTargetWithManualBridgingHeader;

@interface ObjcBasicMixedTargetWithManualBridgingHeaderTestsViaModuleImport : XCTestCase

@end

@implementation ObjcBasicMixedTargetWithManualBridgingHeaderTestsViaModuleImport

- (void)testPublicSwiftAPI {
    // Check that Objective-C compatible Swift API surface is exposed...
    Engine *engine = [[Engine alloc] init];
}

- (void)testPublicObjcAPI {
    // Check that Objective-C API surface is exposed...
    OldPlane *oldPlane = [[OldPlane alloc] init];
    Pilot *pilot = [[Pilot alloc] init];
}

@end
