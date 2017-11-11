import BadCode

let value = badSwiftWithBadC()
print("Unexpected flawless execution of unsafe code: \(value)")
precondition(value == 2, "Unexpected value \(value), expected 2")
