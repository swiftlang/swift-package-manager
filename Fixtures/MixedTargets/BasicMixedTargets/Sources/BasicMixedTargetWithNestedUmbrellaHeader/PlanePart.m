#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetWithNestedUmbrellaHeader/PlanePart.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetWithNestedUmbrellaHeader/PlanePart.h>
// Alternatively, the above `PlanePart` can be imported via:
#import "include/BasicMixedTargetWithNestedUmbrellaHeader/PlanePart.h"
#import "BasicMixedTargetWithNestedUmbrellaHeader/PlanePart.h"

@implementation PlanePart
@end
