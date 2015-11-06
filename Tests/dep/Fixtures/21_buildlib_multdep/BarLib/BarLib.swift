import FooLib
import FooBarLib

class BarLib {
    var bar1: FooLib
    var bar2: FooBarLib
    
    init() {
        let newFoo = FooLib()
        bar1 = newFoo
        let newFooBar = FooBarLib()
        bar2 = newFooBar
    }
}