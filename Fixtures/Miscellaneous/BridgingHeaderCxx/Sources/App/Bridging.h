#pragma once

static inline int cxx_max(int a, int b) {
    auto pick = [](int x, int y) { return x > y ? x : y; };
    return pick(a, b);
}
