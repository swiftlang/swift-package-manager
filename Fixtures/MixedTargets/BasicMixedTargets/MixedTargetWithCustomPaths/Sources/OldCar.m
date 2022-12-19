#import <Foundation/Foundation.h>

// All three import statements should be supported.
#import "OldCar.h"
#import "Public/OldCar.h"
#import "MixedTargetWithCustomPaths/Sources/Public/OldCar.h"


// Import the Swift half of the module.
#import "MixedTargetWithCustomPaths-Swift.h"

// Both import statements should be supported.
#import "Transmission.h"
#import "MixedTargetWithCustomPaths/Sources/Transmission.h"

@interface OldCar ()
@property(nonatomic) Transmission *transmission;
@end

@implementation OldCar
@end
