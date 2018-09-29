#include "Bar/Bar.h"
#include "Foo/Foo.h"

int bar() {
    int a = foo();
    int b = a;
    a = b;
    return a;
}
