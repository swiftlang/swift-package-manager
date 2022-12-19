#import <Foundation/Foundation.h>

#import "OldCar.h"
#import "include/OldCar.h"

// Import the Swift half of the module.
#import "BasicMixedTarget-Swift.h"

#import "Transmission.h"

@interface OldCar ()
@property(nonatomic) Transmission *transmission;
@end

@implementation OldCar
@end
