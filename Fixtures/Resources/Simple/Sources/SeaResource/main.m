#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSBundle *bundle = SWIFTPM_MODULE_BUNDLE;
        NSString *foo = [bundle pathForResource:@"foo" ofType:@"txt"];
        NSData *data = [NSFileManager.defaultManager contentsAtPath:foo];
        NSString *contents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        printf("%s", contents.UTF8String);
    }
    return 0;
}
