/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import SourceControl

import Utility
import func POSIX.exit
import enum PackageLoading.ManifestParseError

import Workspace

public enum Error: Swift.Error {
    case noManifestFound
    case invalidToolchain(problem: String)
    case buildYAMLNotFound(String)
    case repositoryHasChanges(String)
}

extension Error: FixableError {
    public var error: String {
        switch self {
        case .noManifestFound:
            return "no \(Manifest.filename) file found"
        case .invalidToolchain(let problem):
            return "invalid inferred toolchain: \(problem)"
        case .buildYAMLNotFound(let value):
            return "no build YAML found: \(value)"
        case .repositoryHasChanges(let value):
            return "repository has changes: \(value)"
        }
    }

    public var fix: String? {
        switch self {
        case .noManifestFound:
            return "create a file named \(Manifest.filename) or run `swift package init` to initialize a new package"
        case .repositoryHasChanges(_):
            return "stage the changes and reapply them after updating the repository"
        default:
            return nil
        }
    }
}

public func handle(error receivedError: Any) -> Never {
    // If we got AnyError, unwrap it.
    let error: Any
    if case let anyError as AnyError = receivedError {
        error = anyError.underlyingError
    } else {
        error = receivedError
    }

    switch error {
    case ArgumentParserError.unknownOption(let option):
        print(error: "Unknown option \(option). Use --help to list available options")

    case ArgumentParserError.unknownValue(let option, let value):
        print(error: "Unknown value \(value) provided for option \(option). Use --help to list available values")

    case ArgumentParserError.expectedValue(let option):
        print(error: "Option \(option) requires a value. Provide a value using '\(option) <value>' or '\(option)=<value>'")

    case ArgumentParserError.unexpectedArgument(let arg):
        print(error: "Unexpected argument \(arg). Use --help to list available arguments")

    case ArgumentParserError.expectedArguments(let parser, let args):
        print(error: "Expected arguments: \(args.joined(separator: ", ")).\n")
        parser.printUsage(on: stderrStream)

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

    case ManifestParseError.emptyManifestFile:
        print(error: "Empty manifest file is not supported anymore. Use `swift package init` to autogenerate.")

    case ManifestParseError.invalidManifestFormat(let errors):
        print(error: errors)

    case ManifestParseError.runtimeManifestErrors(let errors):
        let errorString = "invalid manifest format; " + errors.joined(separator: ", ")
        print(error: errorString)

    case PackageToolOperationError.insufficientOptions(let usage):
        stderrStream <<< usage <<< "\n"
        
    case GitRepositoryProviderError.gitCloneFailure(let url, let path, let errorOutput):
        print(error: "Failed to clone \(url) to \(path.asString):\n\(errorOutput)")
        
    default:
        print(error: error)
    }

    exit(1)
}

private func print(error: Any) {
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
