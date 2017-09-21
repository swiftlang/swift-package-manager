import CLib

// This is expected to be set with -Xswiftc.
#if !EXTRA_SWIFTC_DEFINE
doesNotCompile()
#endif

foo()

class Bar {
    var bar: Int = 0 
    #if SWIFT_PACKAGE
    #else
    var bar: String = ""
    #endif
}
