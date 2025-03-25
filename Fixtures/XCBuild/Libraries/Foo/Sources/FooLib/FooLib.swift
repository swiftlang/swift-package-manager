import CFooLib
import BarLib

public struct FooInfo {
    public static let name = "Foo \(BarInfo.name) \(CFooInfo.name)"
}