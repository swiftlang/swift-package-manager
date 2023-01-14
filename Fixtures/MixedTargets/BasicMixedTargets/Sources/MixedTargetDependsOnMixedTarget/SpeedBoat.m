#import <Foundation/Foundation.h>

#import "SpeedBoat.h"
#import <SpeedBoat.h>

// Import the mixed target's public headers. Both "..." and <...> style imports
// should resolve.
#import "CarPart.h"
#import <CarPart.h>
#import "Driver.h"
#import <Driver.h>
#import "OldCar.h"
#import <OldCar.h>
#import "BasicMixedTarget-Swift.h"
#import <BasicMixedTarget-Swift.h>

@interface SpeedBoat ()

// The below types comes from the `BasicMixedTarget` module`.
@property(nonatomic, strong) Engine *engine;
@property(nonatomic, strong) Driver *driver;
@end

@implementation SpeedBoat
@end
