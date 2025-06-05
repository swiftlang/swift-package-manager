import Foundation

public struct AwesomeResource {
    public init() {}
    public let hello = try! String(contentsOf: Bundle.module.url(forResource: "hello", withExtension: "txt")!)
}
