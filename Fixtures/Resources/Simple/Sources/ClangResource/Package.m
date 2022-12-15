#import <Foundation/Foundation.h>

#import "Package.h"

@implementation Package

+ (NSBundle *)resourceBundle {
    return SWIFTPM_MODULE_BUNDLE;
}

@end
