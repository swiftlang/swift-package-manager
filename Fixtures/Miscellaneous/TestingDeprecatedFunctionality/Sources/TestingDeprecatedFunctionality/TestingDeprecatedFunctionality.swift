struct TestingDeprecatedFunctionality {
    let newText = "New text."
    @available(*, deprecated, message: "Please use newText instead")
    let text = "Deprecated text."
}
