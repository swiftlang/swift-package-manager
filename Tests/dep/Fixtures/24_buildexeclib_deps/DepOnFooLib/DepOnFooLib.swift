import FooLib

public class DepOnFooLib {
    public var foo: FooLib
    
    public init() {
        foo = FooLib()
    }
}