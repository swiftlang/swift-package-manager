#include "tsan_utils.h"

bool is_tsan_enabled() {
#if defined(__has_feature) && __has_feature(thread_sanitizer)
    return true;
#else
    return false;
#endif
}
