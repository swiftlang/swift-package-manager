class Foo {
    var bar: Int = 0
    #if GOT_EXTRA_ARG
    #else
    var bar: Int = 0
    #endif
}