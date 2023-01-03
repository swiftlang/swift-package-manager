#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetBeta/OldPlane.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetBeta/OldPlane.h>
// Alternatively, the above `OldPlane` can be imported via:
#import "include/BasicMixedTargetBeta/OldPlane.h"
#import "BasicMixedTargetBeta/OldPlane.h"

// Import the Swift part of the module.
#import "BasicMixedTargetBeta-Swift.h"

#import "CabinClass.h"

@interface OldPlane ()
@property(nonatomic, assign) CabinClass cabinClass;
@end

@implementation OldPlane
@end
