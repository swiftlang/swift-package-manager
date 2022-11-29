#import <XCTest/XCTest.h>

@import ClangResource;

@interface ClangResourceTests : XCTestCase
@end

@implementation ClangResourceTests

- (void)testResourceBundleIsNonNil {
    XCTAssertNotNil([Package resourceBundle]);
}

@end
