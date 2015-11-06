The POSIX module wraps C POSIX functions to make them more
suitable for use with Swift.

Generally this means the functions `throw` errors, return
Strings, and have useful named parameters.

For functions that are fine as-is, we re-export them from
the underlying Darwin or Glibc modules.
