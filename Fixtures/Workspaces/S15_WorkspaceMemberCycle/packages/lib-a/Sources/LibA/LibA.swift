import LibB

public enum LibA {
    public static var value: String {
        "lib-a saw \(LibB.name)"
    }
}
