import Foundation

let output = ProcessInfo.processInfo.arguments[1]
try "let stringConstant = \"Hello, World!\"".write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
