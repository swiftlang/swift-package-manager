#include "CxxCountdown.hpp"
// #include "MixedTargetWithCXX_CXXInteropEnabled-Swift.h"
// #include <MixedTargetWithCXX_CXXInteropEnabled/MixedTargetWithCXX_CXXInteropEnabled-Swift.h>
#include <MixedTargetWithCXX_CXXInteropEnabled-Swift.h>
#include <iostream>

CxxCountdown::CxxCountdown(bool printCount) : printCount(printCount) {}

void CxxCountdown::countdown(int x )const {
    if (x < 0)
      std::cout << "[c++] Cannot count down from a negative number.\n";

    if (printCount)
      std::cout << "[c++] T-minus " << x << "... \n";

    if (x == 0)
      std::cout << "[c++] We have liftoff!";

    auto swiftCountdown = MixedTargetWithCXX_CXXInteropEnabled::SwiftCountdown::init(printCount);
    swiftCountdown.countdown(x - 1);
}
