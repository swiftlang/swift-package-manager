// The Swift Programming Language
// https://docs.swift.org/swift-book

public struct Person {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
extension Person: CustomStringConvertible {
    public var description: String {
        return name
    }
}

public func greet(person: Person? = nil) -> String {
    let name = if let person {
        person.name
    } else {
        "World"
    }

    return "Hello, \(name)!"
}
