struct Simple {
    func hello() {}

    @available(*, deprecated, message: "use hello instead")
    func deprecatedHello() {}
}
