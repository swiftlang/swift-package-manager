#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetWithManualBridgingHeader/PlanePart.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetWithManualBridgingHeader/PlanePart.h>
// Alternatively, the above `PlanePart` can be imported via:
#import "include/BasicMixedTargetWithManualBridgingHeader/PlanePart.h"
#import "BasicMixedTargetWithManualBridgingHeader/PlanePart.h"

@implementation PlanePart
@end
