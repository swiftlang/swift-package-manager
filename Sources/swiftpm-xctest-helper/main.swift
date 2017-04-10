/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(macOS)
import XCTest
import func Darwin.C.exit

/// A helper tool to get list of tests from a XCTest Bundle on OSX.
///
/// Usage: swiftpm-xctest-helper <bundle_path> <output_file_path>
/// bundle_path: Path to the XCTest bundle
/// output_file_path: File to write the result into.
///
/// Note: Output is a JSON dictionary. Tests are discovered by 
/// loading the bundle and then iterating the default Test Suite.
func run() throws {

    guard CommandLine.arguments.count == 3 else {
        throw Error.invalidUsage
    }
    let bundlePath = CommandLine.arguments[1].normalizedPath()
    let outputFile = CommandLine.arguments[2].normalizedPath()

    // Note that the bundle might write to stdout while it is being loaded, but we don't try to handle that here.
    // Instead the client should decide what to do with any extra output from this tool.
    guard let bundle = Bundle(path: bundlePath), bundle.load() else {
        throw Error.unableToLoadBundle(bundlePath)
    }
    let suite = XCTestSuite.default()

    let splitSet: Set<Character> = ["[", " ", "]", ":"]

    // Array of test cases. Contains test cases in the format:
    // {
    //     "name": "<test_suite_name>",
    //     "tests": [
    //         {
    //             "name": "test_class_name",
    //             "tests": [
    //                 {
    //                     "name": "test_method_name"
    //                 }
    //             ]
    //         }
    //     ]
    // }
    var testCases = [[String: AnyObject]]()

    for case let testCaseSuite as XCTestSuite in suite.tests {
        let testSuite: [[String: AnyObject]] = testCaseSuite.tests.flatMap({
            guard case let testCaseSuite as XCTestSuite = $0 else { return nil }
            // Get the name of the XCTest subclass with its target name if possible.
            // If the subclass contains atleast one test get the name using reflection,
            // otherwise use the name property (which only gives subclass name).
            let name: String
            if let firstTest = testCaseSuite.tests.first {
                name = String(reflecting: type(of: firstTest))
            } else {
                name = testCaseSuite.name ?? "nil"
            }

            // Collect the test methods.
            let tests: [[String: String]] = testCaseSuite.tests.flatMap({ test in
                guard case let test as XCTestCase = test else { return nil }
                // Split the test description into an array. Description formats:
                // `-[ClassName MethodName]`, `-[ClassName MethodNameAndReturnError:]`
                var methodName = test.description.characters
                    .split(whereSeparator: splitSet.contains)
                    .map(String.init)[2]
                // Unmangle names for Swift test cases which throw.
                if methodName.hasSuffix("AndReturnError") {
                    let endIndex = methodName.index(methodName.endIndex, offsetBy: -14)
                    methodName = String(methodName[methodName.startIndex..<endIndex])
                }
                return ["name": methodName]
            })

            return ["name": name as NSString, "tests": tests as NSArray]
        })
        testCases.append([
            "name": (testCaseSuite.name ?? "nil") as NSString,
            "tests": testSuite as NSArray,
        ])
    }

    // Create output file.
    FileManager.default.createFile(atPath: outputFile, contents: nil, attributes: nil)
    // Open output file for writing.
    guard let file = FileHandle(forWritingAtPath: outputFile) else {
        throw Error.couldNotOpenOutputFile(outputFile)
    }
    // Create output dictionary.
    let output = [
        "name" as NSString: "All Tests" as NSString,
        "tests" as NSString: testCases as NSArray,
    ] as NSDictionary
    // Convert output dictionary to JSON and write to output file.
    let outputData = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
    file.write(outputData)
}

enum Error: Swift.Error {
    case invalidUsage
    case unableToLoadBundle(String)
    case couldNotOpenOutputFile(String)
}

extension String {
    func normalizedPath() -> String {
        var path = self
        if !(path as NSString).isAbsolutePath {
            path = FileManager.default.currentDirectoryPath + "/" + path
        }
        return (path as NSString).standardizingPath
    }
}

do {
    try run()
} catch Error.invalidUsage {
    print("Usage: swiftpm-xctest-helper <bundle_path> <output_file_path>")
    exit(1)
} catch {
    print("error: \(error)")
    exit(1)
}

#else

import func Glibc.exit
print("Only OSX supported.")
exit(1)

#endif
