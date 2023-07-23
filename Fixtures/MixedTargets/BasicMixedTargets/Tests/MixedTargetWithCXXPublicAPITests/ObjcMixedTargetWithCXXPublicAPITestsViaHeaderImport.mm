#import <XCTest/XCTest.h>

#import "CXXSumFinder.hpp"
#import "ObjcCalculator.h"
#import "MixedTargetWithCXXPublicAPI-Swift.h"

@interface ObjcMixedTargetWithCXXPublicAPITestsViaHeaderImport : XCTestCase
@end

@implementation ObjcMixedTargetWithCXXPublicAPITestsViaHeaderImport

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