#import <Foundation/Foundation.h>

#import "include/OldBoat.h"

// Import the mixed target's module.
@import BasicMixedTarget;

@interface OldBoat ()
// The below types comes from the `BasicMixedTarget` module`.
@property(nonatomic, strong) Engine *engine;
@property(nonatomic, strong) Driver *driver;
@end

@implementation OldBoat
@end
