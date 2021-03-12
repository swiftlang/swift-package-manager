import Foundation

// Sample source generator tool that emits a Swift variable declaration of a string containing the hex representation of the contents of a file as a quoted string.  The variable name is the base name of the input file, with the value from an environment value prepended.  The input file is the first argument and the output file is the second.
if ProcessInfo.processInfo.arguments.count != 3 {
    print("usage: MySourceGenBuildTool <input> <output>")
    exit(1)
}
let inputFile = ProcessInfo.processInfo.arguments[1]
let outputFile = ProcessInfo.processInfo.arguments[2]

let variablePrefix = ProcessInfo.processInfo.environment["VARIABLE_NAME_PREFIX"] ?? ""
let variableName = URL(fileURLWithPath: inputFile).deletingPathExtension().lastPathComponent

let inputData = FileManager.default.contents(atPath: inputFile) ?? Data()
let dataAsHex = inputData.map { String(format: "%02hhx", $0) }.joined()
let outputString = "public var \(variablePrefix)\(variableName) = \(dataAsHex.quotedForSourceCode)\n"
let outputData = outputString.data(using: .utf8)
FileManager.default.createFile(atPath: outputFile, contents: outputData)

extension String {
    
    public var quotedForSourceCode: String {
        return "\"" + self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
