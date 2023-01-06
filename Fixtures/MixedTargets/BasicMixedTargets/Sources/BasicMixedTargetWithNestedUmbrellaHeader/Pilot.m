#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetWithNestedUmbrellaHeader/Pilot.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetWithNestedUmbrellaHeader/Pilot.h>
// Alternatively, the above `Pilot` can be imported via:
#import "include/BasicMixedTargetWithNestedUmbrellaHeader/Pilot.h"
#import "BasicMixedTargetWithNestedUmbrellaHeader/Pilot.h"

@implementation Pilot
@end
