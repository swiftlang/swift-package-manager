@import Foundation;
@import BarLib;
#import "CFooLib.h"

@implementation CFooInfo

+ (NSString*)name {
    return [NSString stringWithFormat:@"CFoo %@", [BarInfo name]];
}

@end
