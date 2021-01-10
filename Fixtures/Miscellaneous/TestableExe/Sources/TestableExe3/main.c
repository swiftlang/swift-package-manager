#include <stdio.h>
#include "include/TestableExe3.h"

const char * GetGreeting3() {
    return "Hello, universe";
}

int main() {
    printf("%s!\n", GetGreeting3());
}
