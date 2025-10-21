protocol P {
}
protocol Q {
}

func test1(_: P) {
}

func test2(_: P.Protocol) {
}

func test3() {
    let _: [P?] = []
}

func test4() {
    var x = 42
}

func test5(_: P & Q) {
}
