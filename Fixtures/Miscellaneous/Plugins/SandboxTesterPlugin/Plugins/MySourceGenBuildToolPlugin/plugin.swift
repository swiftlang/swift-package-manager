import PackagePlugin
import Foundation
 
// Check that we can write to the output directory.
let allowedOutputPath = targetBuildContext.pluginWorkDirectory.appending("Foo")
if mkdir(allowedOutputPath.string, 0o777) != 0 {
     throw StringError("unexpectedly could not write to '\(allowedOutputPath)': \(String(utf8String: strerror(errno)))")
}

// Check that we cannot write to the source directory.
let disallowedOutputPath = targetBuildContext.targetDirectory.appending("Bar")
if mkdir(disallowedOutputPath.string, 0o777) == 0 {
     throw StringError("unexpectedly could write to '\(disallowedOutputPath)'")
}


struct StringError: Error, CustomStringConvertible {
    var error: String
    init(_ error: String) {
        self.error = error
    }
    var description: String { error }
}
