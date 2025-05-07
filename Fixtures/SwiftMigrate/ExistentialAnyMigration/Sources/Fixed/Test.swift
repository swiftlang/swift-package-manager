protocol P {
}

func test1(_: any P) {
}

func test2(_: (any P).Protocol) {
}

func test3() {
    let _: [(any P)?] = []
}

func test4() {
    var x = 42
}
