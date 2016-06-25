#include "Foo.h"

int foo() {
    bar();
    int a = 5;
    int b = a;
    a = b;
    return a;
}
