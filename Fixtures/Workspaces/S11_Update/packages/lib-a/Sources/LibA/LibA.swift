import OtherLib

public enum LibA {
    public static func greeting() -> String {
        "Hello from lib-a (\(OtherLib.greeting()))"
    }
}
