#import <Foundation/Foundation.h>

#import "RecyclingCenter.h"

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

@interface RecyclingCenter ()
// The below types come from the `BasicMixedTarget` module.
@property(nullable) Engine *engine;
@property(nullable) Driver *driver;
@property(nullable) OldCar *oldCar;
@property(nullable) CarPart *carPart;
@end

@implementation RecyclingCenter
@end
