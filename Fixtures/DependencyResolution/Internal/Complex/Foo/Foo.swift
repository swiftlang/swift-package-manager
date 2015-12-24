import Bar

func foo() -> String {
    let bar = Bar()
    return bar.cat.sound.description + " " + bar.baz.value
}
