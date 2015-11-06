//Foo is an executable that depends on an executable and a library 

import DepOnFooLib

class Foo {
    var foo: DepOnFooLib
    
    init() {
        foo = DepOnFooLib()
    }
}