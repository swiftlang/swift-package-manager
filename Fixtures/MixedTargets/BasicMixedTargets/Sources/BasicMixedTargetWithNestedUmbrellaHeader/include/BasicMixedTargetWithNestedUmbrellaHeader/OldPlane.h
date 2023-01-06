#import <Foundation/Foundation.h>

#import "Pilot.h"

// The `Engine` type is declared in the Swift part of the module. Such types
// must be forward declared in headers.
@class Engine;

@interface OldPlane : NSObject
// `Engine` is defined in Swift.
@property(nullable) Engine *engine;
// `Pilot` is defined in Objective-C.
@property(nullable) Pilot *pilot;
@end
