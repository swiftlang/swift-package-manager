#import <StaticLibrary.h>
#import <DynamicLibrary.h>

@interface CLibrary: NSObject

@property (nonatomic, readonly) StaticLibrary* staticLibrary;
@property (nonatomic, readonly) DynamicLibrary* dynamicLibrary;

@end