@discardableResult
public func publicFunc() -> Int {
    print("public func")
    return 1
}

@discardableResult
package func packageFunc() -> Int {
    print("package func")
    return 2
}
