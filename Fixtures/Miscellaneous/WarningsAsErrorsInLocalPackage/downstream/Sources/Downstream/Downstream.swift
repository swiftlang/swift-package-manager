import Upstream

@available(*, deprecated, renamed: "newGreet")
public func greet() -> String {
    Upstream.NewAPI()
}

public func newGreet() -> String {
    greet()
}
