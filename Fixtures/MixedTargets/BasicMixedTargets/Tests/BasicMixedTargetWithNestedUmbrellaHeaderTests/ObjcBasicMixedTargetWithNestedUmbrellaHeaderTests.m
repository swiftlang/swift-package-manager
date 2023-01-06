#import <XCTest/XCTest.h>

@import BasicMixedTargetWithNestedUmbrellaHeader;

@interface ObjcBasicMixedTargetWithNestedUmbrellaHeaderTests : XCTestCase

@end

@implementation ObjcBasicMixedTargetWithNestedUmbrellaHeaderTests

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
