@_cdecl("LLVMFuzzerTestOneInput")
public func test(_ start: UnsafeRawPointer, _ count: Int) -> CInt {
    let bytes = UnsafeRawBufferPointer(start: start, count: count)
    _ = bytes.first
    return 0
}

@main
struct Fuzzer {
    static func main() {
        print("regular main called")
    }
}
