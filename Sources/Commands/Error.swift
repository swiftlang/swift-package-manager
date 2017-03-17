/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageLoading
import PackageModel
import SourceControl
import Utility
import func POSIX.exit
import Workspace

enum Error: Swift.Error {
    /// Couldn't find all tools needed by the package manager.
    case invalidToolchain(problem: String)

    /// The root manifest was not found.
    case rootManifestFileNotFound

    /// There were fatal diagnostics during the operation.
    case hasFatalDiagnostics
}

extension Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidToolchain(let problem):
            return problem
        case .rootManifestFileNotFound:
            return "The root manifest was not found"
        case .hasFatalDiagnostics:
            return ""
        }
    }
}

public func handle(error: Any) -> Never {
    switch error {

    // If we got instance of any error, handle the underlying error.
    case let anyError as AnyError:
        handle(error: anyError.underlyingError)

    default:
        _handle(error)
    }

    // Exit with non zero exit-code.
    exit(1)
}

// The name has underscore because of SR-4015.
private func _handle(_ error: Any) {

    switch error {
    case Error.hasFatalDiagnostics:
        break

    case ArgumentParserError.expectedArguments(let parser, _):
        print(error: error)
        parser.printUsage(on: stderrStream)

    case ToolsVersionLoader.Error.malformed(let versionSpecifier, _):
        print(error: "The version specifier '\(versionSpecifier)' is not valid")

    case WorkspaceOperationError.incompatibleToolsVersion(_, let required, let current):
        print(error: "Package requires minimum Swift tools version \(required). Current Swift tools version is \(current)")

    case PinOperationError.notPinned:
        print(error: "The provided package is not pinned")

    case PinOperationError.autoPinEnabled:
        print(error: "Autopinning should be turned off to use this mode. Run 'swift package pin --disable-autopin' to disable autopin")

    case PackageToolOperationError.packageInEditableState:
        print(error: "The provided package is in editable state")

    case PackageToolOperationError.packageNotFound:
        print(error: "The provided package was not found")

    case let error as FixableError:
        print(error: error.error)
        if let fix = error.fix {
            print(fix: fix)
        }

    case Package.Error.noManifest(let url, let version):
        var string = "\(url) has no manifest"
        if let version = version {
            string += " for version \(version)"
        }
        print(error: string)

    case PackageToolOperationError.insufficientOptions(let usage):
        print(error: usage)
        
    default:
        print(error: error)
    }
}

func print(error: Any) {
    // FIXME: We should generalize this.
    if let stdStream = stderrStream as? LocalFileOutputByteStream, let term = TerminalController(stream: stdStream) {
        term.write("error: ", inColor: .red, bold: true)
    } else {
        stderrStream <<< "error: "
    }
    stderrStream <<< "\(error)" <<< "\n"
    stderrStream.flush()
}

private func print(fix: String) {
    // FIXME: We should generalize this.
    if let stdStream = stderrStream as? LocalFileOutputByteStream, let term = TerminalController(stream: stdStream) {
        term.write("fix: ", inColor: .yellow, bold: true)
    } else {
        stderrStream <<< "fix: "
    }
    stderrStream <<< fix <<< "\n"
    stderrStream.flush()
}
