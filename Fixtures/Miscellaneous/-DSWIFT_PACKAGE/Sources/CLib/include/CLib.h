// This is to check a -Xcc arg.
#if !defined(EXTRA_C_DEFINE) || EXTRA_C_DEFINE != 2
#error "unexpected compiler flags"
#endif

void foo(void);
