public enum Library {
    public static var enabledTraits: [String] {
        var traits: [String] = []
        #if FOO
        traits.append("Foo")
        #endif
        #if BAR
        traits.append("Bar")
        #endif
        return traits
    }

    #if BAR
    /// API that only exists when the `Bar` trait is enabled. Test targets using
    /// this API only compile under a trait configuration that enables `Bar`.
    public static func barOnlyAPI() -> String {
        "bar"
    }
    #endif
}
