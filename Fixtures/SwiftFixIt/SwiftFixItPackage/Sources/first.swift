func foo(_: P, _: P) {}

func throwing() throws -> Int {}

func foo() throws {
    do {
        var x = 0
    }
    do {
        let x = throwing()
    }
}
