/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Verbosity: Int {
    case Concise
    case Verbose
    case Debug

    public init(rawValue: Int) {
        switch rawValue {
        case Int.min...0:
            self = .Concise
        case 1:
            self = .Verbose
        default:
            self = .Debug
        }
    }

    public var ccArgs: [String] {
        switch self {
        case .Concise:
            return []
        case .Verbose:
            // the first level of verbosity is passed to llbuild itself
            return []
        case .Debug:
            return ["-v"]
        }
    }
}

public var verbosity = Verbosity.Concise


import func libc.fputs
import var libc.stderr

public class StandardErrorOutputStream: OutputStream {
    public func write(_ string: String) {
        libc.fputs(string, libc.stderr)
    }
}

public var stderr = StandardErrorOutputStream()



import func POSIX.prettyArguments

private let ESC = "\u{001B}"
private let CSI = "\(ESC)["

internal func prettyArguments(_ arguments: [String]) -> String {
    guard arguments.count > 0 else { return "" }

    var arguments = arguments
    let arg0 = blue(arguments.removeFirst())

    return arg0 + " " + POSIX.prettyArguments(arguments)
}

internal func printArgumentsIfVerbose(_ arguments: [String]) {
    if verbosity != .Concise {
        print(prettyArguments(arguments))
    }
}


import func libc.fflush
import var libc.stdout
import enum POSIX.Error

public func system(_ arguments: String..., environment: [String:String] = [:], message: String?) throws {
    var out = ""
    do {
        if Utility.verbosity == .Concise {
            if let message = message {
                print(message)
                fflush(stdout)  // ensure we display `message` before git asks for credentials
            }
            try Utility.popen(arguments, redirectStandardError: true, environment: environment) { line in
                out += line
            }
        } else {
            try system(arguments, environment: environment)
        }
    } catch {
        if verbosity == .Concise {
            print(prettyArguments(arguments), to: &stderr)
            print(out, to: &stderr)
        }
        throw error
    }
}

internal func blue(_ input: String) -> String {
    return CSI + "34m" + input + CSI + "0m"
}
