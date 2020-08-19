#if defined(__linux__)

#include <errno.h>

#include "process.h"

int SPM_posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *restrict file_actions, const char *restrict path) {
#if defined(__GLIBC__)
#  if __GLIBC_PREREQ(2, 29)
    return posix_spawn_file_actions_addchdir_np(file_actions, path);
#  else
    return ENOSYS;
#  endif
#else
    return ENOSYS;
#endif
}

bool SPM_posix_spawn_file_actions_addchdir_np_supported() {
#if defined(__GLIBC__)
#  if __GLIBC_PREREQ(2, 29)
    return true;
#  else
    return false;
#  endif
#else
    return false;
#endif
}

#endif
