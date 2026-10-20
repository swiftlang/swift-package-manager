#import "Bridge.h"

#import "MixedLib-Swift.h"

int bridge_value(void) {
    return (int)[Greeter rawValue];
}
