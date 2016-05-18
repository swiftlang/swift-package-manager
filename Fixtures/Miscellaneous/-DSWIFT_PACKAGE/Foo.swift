class Foo{
    var bar: Int = 0 
    #if SWIFT_PACKAGE
    #else
    var bar: String = ""
    #endif
}
