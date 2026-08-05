#include "CUpstream.h"

int cUpstreamValue(void) {
    // Intentionally omit the `return` statement. This emits -Wreturn-type
    // ("control reaches end of non-void function"), which is enabled by default.
    // The manifest promotes it to an error via treatAllWarnings/treatWarning when
    // this package is the root, but the setting is stripped (and warnings
    // suppressed) when the package is consumed as a remote dependency.
}
