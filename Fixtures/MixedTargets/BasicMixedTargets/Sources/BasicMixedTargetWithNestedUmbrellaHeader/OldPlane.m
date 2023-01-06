#import <Foundation/Foundation.h>

// The below import syntax resolves to the `"BasicMixedTargetWithNestedUmbrellaHeader/OldPlane.h"`
// path within the public headers directory. It is not related to a
// framework style import.
#import <BasicMixedTargetWithNestedUmbrellaHeader/OldPlane.h>
// Alternatively, the above `OldPlane` can be imported via:
#import "include/BasicMixedTargetWithNestedUmbrellaHeader/OldPlane.h"
#import "BasicMixedTargetWithNestedUmbrellaHeader/OldPlane.h"

// Import the Swift part of the module.
#import "BasicMixedTargetWithNestedUmbrellaHeader-Swift.h"

#import "CabinClass.h"

@interface OldPlane ()
@property(nonatomic, assign) CabinClass cabinClass;
@end

@implementation OldPlane
@end
