import SomeLib

public enum LibA {
    public static func greeting() -> String {
        "Hello from lib-a (\(SomeLib.greeting()))"
    }
}
