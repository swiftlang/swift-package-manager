import XCTest
import Basic
import Foundation

public func mktmpdir(
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line,
    body: (AbsolutePath) throws -> Void
) {
    do {
        let cleanedFunction = function.description
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
        let tmpDir = try TemporaryDirectory(prefix: "libgit-tests-\(cleanedFunction)")
        try body(tmpDir.path)
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

