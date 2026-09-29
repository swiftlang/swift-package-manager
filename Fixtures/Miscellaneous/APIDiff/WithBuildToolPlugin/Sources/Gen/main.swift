import Foundation

let out = CommandLine.arguments[1]
try "public let generated = 1\n".write(toFile: out, atomically: true, encoding: .utf8)
