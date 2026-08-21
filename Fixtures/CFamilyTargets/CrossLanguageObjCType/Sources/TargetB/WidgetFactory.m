#import "WidgetFactory.h"

Widget * _Nonnull makeWidget(void) {
    return [[Widget alloc] initWithValue:42];
}
