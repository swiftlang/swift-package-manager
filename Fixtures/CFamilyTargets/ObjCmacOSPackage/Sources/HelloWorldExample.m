#import <Foundation/Foundation.h>
#import "HelloWorldExample.h"

@implementation HelloWorld
- (NSString *)hello:(NSString *)name {
  if(!name) {
    name = @"World";
  }
  return [NSString stringWithFormat:@"Hello, %@!", name];
}
@end
