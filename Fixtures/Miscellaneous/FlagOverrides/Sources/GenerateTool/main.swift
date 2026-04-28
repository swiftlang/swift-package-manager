import Foundation

#if ONE
let flag = "ONE"
#elseif TWO
let flag = "TWO"
#else
let flag = "NONE"
#endif

let outputFile = ProcessInfo.processInfo.arguments[1]
let source = """
func generatedFunction() {
    print("Plugin tool flag: \(flag)")
}
"""
try source.write(toFile: outputFile, atomically: true, encoding: .utf8)
