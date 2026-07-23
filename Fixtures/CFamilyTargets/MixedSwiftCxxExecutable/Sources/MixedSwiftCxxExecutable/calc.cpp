#include "calc.h"
#include <vector>

int cpp_sum(int n) {
    std::vector<int> values;
    for (int i = 1; i <= n; ++i) {
        values.push_back(i);
    }
    int sum = 0;
    for (int value : values) {
        sum += value;
    }
    return sum;
}
