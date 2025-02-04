// The Swift Programming Language
// https://docs.swift.org/swift-book

import AllPlatforms

#if os(Windows)
    import WindowsOnly
#else
    #if os(macOS)
    import MacOSOnly
    #else
        #if os(linux)
        import LinuxOnly
        #endif
    #endif
#endif

let platform = try getPlatform()
print("Hello, world on \(platform)!  OSplatform: \(OSPlatform.name)")
