import ArgumentParser
import Foundation
import MySourceGenToolLib

// Sample source generator tool that just emits the hex representation of the contents of a file as a quoted string.
struct MySourceGenTool: ParsableCommand {
    @Argument() var inputFile: String
    @Argument() var outputFile: String
    
    func run() {
        let inputData = FileManager.default.contents(atPath: inputFile) ?? Data()
        let dataAsHex = inputData.map { String(format: "%02hhx", $0) }.joined()
        let outputString = "public var data = \(dataAsHex.quotedForSourceCode)\n"
        let outputData = outputString.data(using: .utf8)
        FileManager.default.createFile(atPath: outputFile, contents: outputData)
    }
}

MySourceGenTool.main()
