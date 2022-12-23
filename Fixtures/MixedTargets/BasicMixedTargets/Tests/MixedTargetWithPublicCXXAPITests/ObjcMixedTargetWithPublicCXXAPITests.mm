#import <XCTest/XCTest.h>

@import MixedTargetWithPublicCXXAPI;

@interface ObjcMixedTargetWithPublicCXXAPITests : XCTestCase
@end

@implementation ObjcMixedTargetWithPublicCXXAPITests

- (void)testPublicObjcAPI {
    XCTAssertEqual([ObjcCalculator factorialForInt:5], 120);
    XCTAssertEqual([ObjcCalculator sumX:1 andY:2], 3);
}

- (void)testPublicCXXAPI {
    CXXSumFinder sf;
    XCTAssertEqual(sf.sum(1,2), 3);
}

@end
