#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetWithManualBridgingHeader/Pilot.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetWithManualBridgingHeader/Pilot.h>
// Alternatively, the above `Pilot` can be imported via:
#import "include/BasicMixedTargetWithManualBridgingHeader/Pilot.h"
#import "BasicMixedTargetWithManualBridgingHeader/Pilot.h"

@implementation Pilot
@end
