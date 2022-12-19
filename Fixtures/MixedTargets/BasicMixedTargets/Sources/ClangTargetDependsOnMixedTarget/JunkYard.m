#import <Foundation/Foundation.h>

#import "include/JunkYard.h"

@import BasicMixedTarget;

@interface JunkYard ()
// The below types come from the `BasicMixedTarget` module.
@property(nullable) Engine *engine;
@property(nullable) Driver *driver;
@property(nullable) OldCar *oldCar;
@end

@implementation JunkYard
@end