import Foundation

let inputs = CommandLine.arguments.dropFirst().dropLast()
let output = CommandLine.arguments.last!

var string = ""

for input in inputs {
    string += try String(contentsOfFile: input)
}

let contents = """
func print_generated_data() {
    print(\"""
\(string)
\""")
}

"""

try contents.write(toFile: output, atomically: true, encoding: .utf8)

