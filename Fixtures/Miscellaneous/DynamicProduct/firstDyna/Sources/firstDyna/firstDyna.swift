import Core

public func hello() -> String {
    return String(cString: Core.hello())
}
