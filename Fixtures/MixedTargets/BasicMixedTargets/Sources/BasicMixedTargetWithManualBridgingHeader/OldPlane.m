#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetWithManualBridgingHeader/OldPlane.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetWithManualBridgingHeader/OldPlane.h>
// Alternatively, the above `OldPlane` can be imported via:
#import "include/BasicMixedTargetWithManualBridgingHeader/OldPlane.h"
#import "BasicMixedTargetWithManualBridgingHeader/OldPlane.h"

// Import the Swift part of the module.
#import "BasicMixedTargetWithManualBridgingHeader-Swift.h"

#import "CabinClass.h"

@interface OldPlane ()
@property(nonatomic, assign) CabinClass cabinClass;
@end

@implementation OldPlane
@end
