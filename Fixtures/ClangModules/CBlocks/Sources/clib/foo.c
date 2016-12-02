#include "foo.h"

int operate(int a, int b, Operation operation) {
    return operation(a,b);
}

int addOperation(int a, int b) {
    return operate(a, b, ^int(int a, int b) {
        return a+b;
    });
}
