/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.isatty
import var Utility.stderr
import PackageType
import libc

public enum CommandLineError: ErrorType {
    public enum UsageMode {
        case Print, Imply
    }
    case InvalidUsage(String, UsageMode)
}

public enum Error: ErrorType {
    case NoManifestFound
    case NoTargetsFound
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .NoManifestFound:
            return "no \(Manifest.filename) file found"
        case .NoTargetsFound:
            return "no targets found for this file layout\n" +
            "refer: https://github.com/apple/swift-package-manager/blob/master/Documentation/SourceLayouts.md"
        }
    }
}

@noreturn public func handleError(msg: Any, usage: ((String) -> Void) -> Void) {
    switch msg {
    case CommandLineError.InvalidUsage(let hint, let mode):
        perror("invalid usage: \(hint)")

        if isatty(fileno(libc.stdin)) {
            switch mode {
            case .Imply:
                print("enter `swift build --help' for usage information", toStream: &stderr)
            case .Print:
                print("", toStream: &stderr)
                usage { print($0, toStream: &stderr) }
            }
        }
    default:
        perror(msg)
    }

    exit(1)
}

private func red(input: Any) -> String {
    let input = "\(input)"
    let ESC = "\u{001B}"
    let CSI = "\(ESC)["
    return CSI + "31m" + input + CSI + "0m"
}

private func perror(msg: Any) {
    if !isatty(fileno(libc.stderr)) {
        print("swift-build: error:", msg, toStream: &stderr)
    } else {
        print(red("error:"), msg, toStream: &stderr)
    }
}
