#import <XCTest/XCTest.h>

@import MixedTargetWithPublicCXXAPI;

@interface ObjcMixedTargetWithPublicCXXAPITestsViaModuleImport : XCTestCase
@end

@implementation ObjcMixedTargetWithPublicCXXAPITestsViaModuleImport

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
