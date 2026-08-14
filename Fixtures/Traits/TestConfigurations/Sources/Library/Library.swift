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
}
