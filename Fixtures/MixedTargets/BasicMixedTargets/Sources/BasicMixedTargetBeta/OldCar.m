#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetBeta/OldCar.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetBeta/OldCar.h>
// Alternatively, the above `OldCar` can be imported via:
#import "include/BasicMixedTargetBeta/OldCar.h"
#import "BasicMixedTargetBeta/OldCar.h"

// Import the Swift part of the module.
#import "BasicMixedTargetBeta-Swift.h"

#import "Transmission.h"

@interface OldCar ()
@property(nonatomic) Transmission *transmission;
@end

@implementation OldCar
@end
