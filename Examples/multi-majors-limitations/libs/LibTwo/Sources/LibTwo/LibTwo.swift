// Written against the plain module name; the prototype is expected to alias it behind the scenes.
import Shared

public enum LibTwo {
    /// Which Shared major this library was actually compiled against.
    public static var sharedMajor: Int { SharedInfo.major }

    /// Public API that exposes a type from Shared 2.x.
    public static func makeToken(_ value: String) -> Token { Token(value) }
    public static func describe(_ token: Token) -> String { "LibTwo sees \(token)" }

    /// Touches Shared's process-global state, then returns everything that state contains.
    public static func registerAndDump() -> [String] {
        SharedInfo.register("LibTwo")
        return SharedInfo.registry
    }

    public static var tokenTypeName: String { SharedInfo.tokenTypeName }
}
