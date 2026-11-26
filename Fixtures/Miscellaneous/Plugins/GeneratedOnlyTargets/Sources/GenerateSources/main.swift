import Foundation

let arguments = CommandLine.arguments
let input = try String(contentsOfFile: arguments[1], encoding: .utf8)
let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines))!
let source: String = switch arguments[3] {
case "GeneratedExecutable":
    "print(\(value))"
case "GeneratedTests":
    "import Testing\nimport GeneratedLibrary\n@Test func generatedAnswer() { #expect(answer == \(value)) }"
default:
    "public let answer = \(value)"
}
try source.write(toFile: arguments[2], atomically: true, encoding: .utf8)
