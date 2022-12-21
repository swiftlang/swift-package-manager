#import <Foundation/Foundation.h>

// This type is Swift compatible and used in `NewCar`.
//
// Class prefix is needed to avoid conflict with identical type when building
// the test executable. This should not be needed in real packages as they
// likely would not have multiple types with the same name like in this
// test package.
NS_SWIFT_NAME(Driver)
@interface XYZDriver : NSObject
@property(nonnull) NSString* name;
@end
