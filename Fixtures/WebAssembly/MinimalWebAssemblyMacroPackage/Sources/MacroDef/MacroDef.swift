@freestanding(expression)
public macro stringify<T>(_ value: T) -> String = #externalMacro(module: "MacroImpl", type: "StringifyMacro")
