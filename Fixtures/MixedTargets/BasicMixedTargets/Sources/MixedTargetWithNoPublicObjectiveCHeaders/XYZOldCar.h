#import <Foundation/Foundation.h>

#import "XYZDriver.h"

// The `Engine` type is declared in the Swift part of the module. Such types
// must be forward declared in headers.
@class Engine;

// Class prefix is needed to avoid conflict with identical type when building
// the test executable. This should not be needed in real packages as they
// likely would not have multiple types with the same name like in this
// test package.
@interface XYZOldCar : NSObject
// `Engine` is defined in Swift.
@property(nullable) Engine *engine;
// `Driver` is defined in Objective-C.
@property(nullable) XYZDriver *driver;
@end
