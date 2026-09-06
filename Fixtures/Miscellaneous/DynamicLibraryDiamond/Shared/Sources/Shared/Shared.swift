nonisolated(unsafe) private var counter = 0

public func bump() -> Int {
    counter += 1
    return counter
}
