public func executeDoubleFree() {
    let size = 512

    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: size, alignment: 1)
    buffer[0] = 0
    buffer.deallocate()
    buffer.deallocate()
    print(buffer[0])
}
