func foo(_: any P, _: any P) {}

func throwing() throws -> Int {}

func foo() throws {
    do {
        _ = 0
    }
    do {
        _ = try throwing()
    }
}
