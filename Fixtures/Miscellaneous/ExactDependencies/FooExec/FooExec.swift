import FooLib1
import FooLib2

public class FooExec {
    public var foo: FooLib1
    public var bar: FooLib2
    
    public init() {
        foo = FooLib1()
        bar = FooLib2() 
    }
}
