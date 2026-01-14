public func GetGreeting1() -> String {
    return String(decoding: PackageResources.foo_txt, as: UTF8.self)
}

print("\(GetGreeting1())!")
