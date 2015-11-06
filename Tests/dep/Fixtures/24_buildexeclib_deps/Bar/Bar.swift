//Bar is an executable that depends on two libraries

import DepOnFooLib
import BarLib

class Foo {
    var foo: DepOnFooLib
    var bar: BarLib
    
    init() {
        foo = DepOnFooLib()
        bar = BarLib()
    }
}