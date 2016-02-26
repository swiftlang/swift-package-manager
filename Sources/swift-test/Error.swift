/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

enum Error: ErrorProtocol {
    case DebugYAMLNotFound
    case TestsExecutableNotFound
}

extension Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .DebugYAMLNotFound:
            return "build the package using `swift build` before running tests"
        case .TestsExecutableNotFound:
            return "no tests found to execute, create a test-module in `Tests` directory"
        }
    }
}
