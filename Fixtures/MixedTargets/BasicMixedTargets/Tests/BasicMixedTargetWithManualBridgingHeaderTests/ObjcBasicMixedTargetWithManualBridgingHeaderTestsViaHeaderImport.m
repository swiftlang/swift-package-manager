#import <XCTest/XCTest.h>

// Import the target via header imports.
#import <BasicMixedTargetWithManualBridgingHeader/BasicMixedTargetWithManualBridgingHeader.h>
#import <BasicMixedTargetWithManualBridgingHeader/OldPlane.h>
#import <BasicMixedTargetWithManualBridgingHeader/Pilot.h>
#import <BasicMixedTargetWithManualBridgingHeader/PlanePart.h>
#import <BasicMixedTargetWithManualBridgingHeader-Swift.h>

@interface ObjcBasicMixedTargetWithManualBridgingHeaderTestsViaHeaderImport : XCTestCase

@end

@implementation ObjcBasicMixedTargetWithManualBridgingHeaderTestsViaHeaderImport

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
