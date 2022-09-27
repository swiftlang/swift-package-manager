public struct linuxOnly {
    public private(set) var text = "Hello, World!"

    public init() {
#if os(Linux)
print("bestOS")
#else
#error("not linux")
#endif
    }
}
