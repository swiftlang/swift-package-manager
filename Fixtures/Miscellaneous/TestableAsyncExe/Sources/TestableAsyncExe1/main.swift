public func GetAsyncGreeting1() async -> String {
    return "Hello, async world"
}

await print("\(GetAsyncGreeting1())!")
