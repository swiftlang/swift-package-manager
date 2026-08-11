@available(*, deprecated, renamed: "NewAPI")
public func deprecatedFunction() -> String {
    "hello from upstream"
}

public func NewAPI() -> String {
    deprecatedFunction()
}
