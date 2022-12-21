#import <Foundation/Foundation.h>

// Both import statements should be supported.
#import "OldCar.h"
#import "include/OldCar.h"

// Import the Swift half of the module.
#import "MixedTargetWithCustomModuleMapAndResources-Swift.h"

@implementation OldCar
@end
