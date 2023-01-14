#import <Foundation/Foundation.h>

#import "include/JunkYard.h"

// Import the mixed target's module.
@import BasicMixedTarget;

@interface JunkYard ()
// The below types come from the `BasicMixedTarget` module.
@property(nullable) Engine *engine;
@property(nullable) Driver *driver;
@property(nullable) OldCar *oldCar;
@property(nullable) CarPart *carPart;
@end

@implementation JunkYard
@end
