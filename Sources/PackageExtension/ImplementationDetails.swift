/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

// The way in which SwiftPM communicates with the package extension is an im-
// plementation detail, but the way it currently works is that the extension
// is compiled (in a very similar way to the package manifest) and then run in
// a sandbox. Currently it is passed the JSON encoded input structure as the
// last command line argument; however, it this will likely change to instead
// read it from stdin, since that avoids any command line length limitation.
// Any generated commands and diagnostics are emitted on stdout after a zero
// byte; this allows regular output, such as print statements for debugging,
// to be emitted to SwiftPM verbatim. SwiftPM tries to interpret any stdout
// contents after the last zero byte as a JSON encoded output struct in UTF-8
// encoding; any failure to decode it is considered a protocol failure. The
// exit code of the compiled extension determines success or failure (though
// failure to decode the output is also considered a failure to run the ex-
// tension).

/// Private constructor for the TargetBuildContext.  Expects the JSON form of
/// this structure to be in the last command line argument.  Also registers a
/// block to emit the output data at the end of the process.
func CreateTargetBuildContext() -> TargetBuildContext {
    // Register a block to emit the JSON form of the output for SwiftPM to read.
    atexit {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(output)
        fputc(0, stdout)
        fputs(String(data: data, encoding: .utf8)!, stdout)
        fflush(stdout)
    }
    // Look for the input JSON as the last argument of the invocation.
    guard let data = ProcessInfo.processInfo.arguments.last?.data(using: .utf8) else {
        output.diagnostics.append(Diagnostic(severity: .error, message: "Expected last argument to contain JSON input data in UTF-8 encoding, but didn't find it.", file: nil, line: nil))
        exit(1)
    }
    let buildContext: TargetBuildContext
    do {
        let decoder = JSONDecoder()
        buildContext = try decoder.decode(TargetBuildContext.self, from: data)
    } catch {
        output.diagnostics.append(Diagnostic(severity: .error, message: "\(error)", file: nil, line: nil))
        exit(1)
    }
    return buildContext
}

/// Private structures containing the information to send back to SwiftPM.

struct Command: Encodable {
    let executable: Path
    let arguments: [String]
    let workingDirectory: Path?
    let environment: [String: String]?
    let displayName: String?
    let inputPaths: [Path]
    let outputPaths: [Path]
    let derivedSourcePaths: [Path]
}

struct Diagnostic: Encodable {
    enum Severity: String, Encodable {
        case error, warning, remark
    }

    let severity: Severity
    let message: String
    let file: Path?
    let line: Int?
}

struct OutputStruct: Encodable {
    let version: Int
    var diagnostics: [Diagnostic] = []
    var commands: [Command] = []
    var generatedFilePaths: [String] = []
    var prebuildOutputDirectories: [String] = []
}

var output = OutputStruct(version: 1)
