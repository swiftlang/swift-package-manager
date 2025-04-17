public func GetAsyncGreeting2() async -> String {
    return "Hello, async planet"
}

await print("\(GetAsyncGreeting2())!")
