import Foundation

if ProcessInfo.processInfo.arguments.count != 3 {
    print("usage: SourceGenTool <input> <output>")
    exit(1)
}
let inputFile = ProcessInfo.processInfo.arguments[1]
let outputFile = ProcessInfo.processInfo.arguments[2]

let variableName = URL(fileURLWithPath: inputFile).deletingPathExtension().lastPathComponent
let inputData = FileManager.default.contents(atPath: inputFile) ?? Data()
let inputString = String(data: inputData, encoding: .utf8) ?? ""
let source = "public let \(variableName) = \"\(inputString.trimmingCharacters(in: .whitespacesAndNewlines))\"\n"
FileManager.default.createFile(atPath: outputFile, contents: source.data(using: .utf8))
