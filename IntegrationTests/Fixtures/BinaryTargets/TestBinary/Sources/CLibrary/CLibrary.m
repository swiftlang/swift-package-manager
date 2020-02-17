#import "CLibrary.h"

@implementation CLibrary

- (instancetype)init {
    self = [super init];
    _staticLibrary = [StaticLibrary new];
    _dynamicLibrary = [DynamicLibrary new];
    return self;
}

@end