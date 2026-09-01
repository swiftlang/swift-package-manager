import LibA

public enum LibB {
    public static let name = "lib-b"

    public static var value: String {
        "lib-b saw \(LibA.value)"
    }
}
