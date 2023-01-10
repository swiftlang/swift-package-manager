#import <XCTest/XCTest.h>

@import MixedTargetWithPublicCXXAPI;

@interface ObjcMixedTargetWithPublicCXXAPIViaModuleImportTests : XCTestCase
@end

@implementation ObjcMixedTargetWithPublicCXXAPIViaModuleImportTests

- (void)testPublicObjcAPI {
    XCTAssertEqual([ObjcCalculator factorialForInt:5], 120);
    XCTAssertEqual([ObjcCalculator sumX:1 andY:2], 3);
}

- (void)testPublicSwiftAPI {
    XCTAssertEqualObjects([Factorial text], @"Hello, World!");
}

- (void)testPublicCXXAPI {
    CXXSumFinder sf;
    XCTAssertEqual(sf.sum(1,2), 3);
}

@end
