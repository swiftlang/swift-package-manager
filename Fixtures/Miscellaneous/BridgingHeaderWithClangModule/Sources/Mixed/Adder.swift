public func compute() -> Int32 {
    return c_add(1, 2) + Int32(bridged_value())
}
