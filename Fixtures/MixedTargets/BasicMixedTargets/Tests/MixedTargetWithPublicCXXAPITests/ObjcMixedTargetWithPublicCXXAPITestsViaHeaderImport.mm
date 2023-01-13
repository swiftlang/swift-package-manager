#import <XCTest/XCTest.h>

#import "CXXSumFinder.hpp"
#import "ObjcCalculator.h"
#import "MixedTargetWithPublicCXXAPI-Swift.h"

@interface ObjcMixedTargetWithPublicCXXAPITestsViaHeaderImport : XCTestCase
@end

@implementation ObjcMixedTargetWithPublicCXXAPITestsViaHeaderImport

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