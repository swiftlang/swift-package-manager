public protocol Tag {}

public struct Boxed<T: Tag> {
    public let value: Int
    public init(_ value: Int) { self.value = value }
}

public enum H1: Tag {}
