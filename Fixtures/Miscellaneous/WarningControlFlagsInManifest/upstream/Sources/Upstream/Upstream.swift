@available(*, deprecated, renamed: "NewAPI")
public func deprecatedFunction() -> String {
    "hello from upstream"
}

public func NewAPI() -> String {
    // Calling the deprecated function emits a DeprecatedDeclaration warning within
    // upstream itself. When upstream is built as the root package its manifest
    // promotes that warning to an error; when it is consumed as a remote
    // dependency the warning-control settings are stripped and warnings suppressed.
    deprecatedFunction()
}
