protocol P {
}

func test1(_: P) {
}

func test2(_: P.Protocol) {
}

func test3() {
    let _: [P?] = []
}
