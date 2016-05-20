#if os(OSX)

import XCTest
import Foundation

enum Error: ErrorProtocol {
    case invalidUsage
    case unableToLoadBundle(String)
}

do {
    guard Process.arguments.count == 2 else {
        throw Error.invalidUsage
    }
    var bundlePath = Process.arguments[1]
    if !(bundlePath as NSString).isAbsolutePath {
        bundlePath = NSFileManager.default().currentDirectoryPath + "/" + bundlePath
    }
    bundlePath = (bundlePath as NSString).standardizingPath

    guard let bundle = NSBundle(path: bundlePath) where bundle.load() else {
        throw Error.unableToLoadBundle(bundlePath)
    }
    
    let suite = XCTestSuite.default()

    let splitSet: Set<Character> = ["[", " ", "]", ":"]
    for case let testCaseSuite as XCTestSuite in suite.tests {
        for case let testCaseSuite as XCTestSuite in testCaseSuite.tests {
            for case let test as XCTestCase in testCaseSuite.tests {
                let exploded = test.description.characters.split(isSeparator: splitSet.contains).map(String.init)
                let moduleName = String(String(reflecting: test.dynamicType).characters.split(separator: ".").first!)
                let className = exploded[1]
                var methodName = exploded[2]
                if methodName.hasSuffix("AndReturnError") {
                    methodName = methodName[methodName.startIndex..<methodName.index(methodName.endIndex, offsetBy: -14)]
                }
                print("\(moduleName).\(className)/\(methodName)")
            }
            print()
        }
    }
} catch Error.invalidUsage {
    print("Usage: spm-test-finder <bundle_path>")
} catch {
    print("error: \(error)")
}

#else
print("Only OSX supported.")
#endif
