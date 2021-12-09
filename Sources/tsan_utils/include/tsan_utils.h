#include <stdbool.h>

/// returns true if the current build supports the thread-sanitizer.
extern bool is_tsan_enabled(void);
