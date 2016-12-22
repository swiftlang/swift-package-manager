/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel

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

public func handle(error: Any) -> Never {

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

    case ManifestParseError.emptyManifestFile:
        print(error: "Empty manifest file is not supported anymore. Use `swift package init` to autogenerate.")

    case ManifestParseError.invalidManifestFormat(let errors):
        print(error: errors)

    case ManifestParseError.runtimeManifestErrors(let errors):
        let errorString = "invalid manifest format; " + errors.joined(separator: ", ")
        print(error: errorString)

    case PackageToolOperationError.insufficientOptions(let usage):
        print(usage, to: &stderr)
    default:
        print(error: error)
    }

    exit(1)
}

private func print(error: Any) {
    if ColorWrap.isAllowed(for: .stdErr) {
        print(ColorWrap.wrap("error:", with: .Red, for: .stdErr), error, to: &stderr)
    } else {
        let cmd = AbsolutePath(CommandLine.arguments.first!, relativeTo:currentWorkingDirectory).basename
        print("\(cmd): error:", error, to: &stderr)
    }
}

private func print(fix: String) {
    if ColorWrap.isAllowed(for: .stdErr) {
        print(ColorWrap.wrap("fix:", with: .Yellow, for: .stdErr), fix, to: &stderr)
    } else {
        print("fix:", fix, to: &stderr)
    }
}
