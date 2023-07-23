#import <XCTest/XCTest.h>

#import "XYZCxxSumFinder.hpp"
#import "XYZObjcCalculator.h"
#import "MixedTargetWithCXXPublicAPIAndCustomModuleMap-Swift.h"

@interface ObjcMixedTargetWithCXXPublicAPIAndCustomModuleMapTestsViaHeaderImport : XCTestCase
@end

@implementation ObjcMixedTargetWithCXXPublicAPIAndCustomModuleMapTestsViaHeaderImport

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