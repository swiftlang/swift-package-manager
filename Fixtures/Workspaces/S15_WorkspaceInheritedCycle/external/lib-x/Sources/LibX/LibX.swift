import LibA

public enum LibX {
    public static let name = "lib-x"

    public static var value: String {
        "lib-x saw \(LibA.value)"
    }
}
