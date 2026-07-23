#include "mul.h"
#include <vector>

int cpp_multiply(int a, int b) {
    std::vector<int> values;
    for (int i = 0; i < b; ++i) {
        values.push_back(a);
    }
    int sum = 0;
    for (int value : values) {
        sum += value;
    }
    return sum;
}
