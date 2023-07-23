#import <XCTest/XCTest.h>

@import MixedTargetWithCXXPublicAPIAndCustomModuleMap;

@interface ObjcMixedTargetWithCXXPublicAPIAndCustomModuleMapTestsViaModuleImport : XCTestCase
@end

@implementation ObjcMixedTargetWithCXXPublicAPIAndCustomModuleMapTestsViaModuleImport

- (void)testPublicObjcAPI {
    XCTAssertEqual([XYZObjcCalculator factorialForInt:5], 120);
    XCTAssertEqual([XYZObjcCalculator sumX:1 andY:2], 3);
}

- (void)testPublicSwiftAPI {
    XCTAssertEqualObjects([Factorial text], @"Hello, World!");
}

- (void)testPublicCXXAPI {
    XYZCxxSumFinder sf;
    XCTAssertEqual(sf.sum(1,2), 3);
}

@end
