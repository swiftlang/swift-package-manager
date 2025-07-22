struct Simple {
    var a = 1
    let b = 42
    func upper(_ input: String) -> String {
        return input.uppercased()
    }
}

import Playgrounds

#Playground {
    let s = Simple()
    print("a is \(s.a)")
}

#Playground("Simple.b") {
    let s = Simple()
    print("b is \(s.b)")
}

#Playground("Upper") {
    let s = Simple()
    let upperFoo = s.upper("foo")
    print("Upper foo is \(upperFoo)")
}
