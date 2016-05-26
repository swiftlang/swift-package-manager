/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import libc

import enum Utility.ColorWrap
import enum Utility.Stream
import func Utility.isTTY
import var Utility.stderr

public enum Error: ErrorProtocol {
    case noManifestFound
    case invalidToolchain
    case invalidInstallation(String)
    case invalidSwiftExec(String)
    case buildYAMLNotFound(String)
    case repositoryHasChanges(String)
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noManifestFound:
            return "no \(Manifest.filename) file found"
        case .invalidToolchain:
            return "invalid inferred toolchain"
        case .invalidInstallation(let prefix):
            return "invalid or incomplete Swift toolchain:\n    \(prefix)"
        case .invalidSwiftExec(let value):
            return "invalid SWIFT_EXEC value: \(value)"
        case .buildYAMLNotFound(let value):
            return "no build YAML found: \(value)"
        case .repositoryHasChanges(let value):
            return "repository has changes: \(value)"
        }
    }
}

@noreturn public func handle(error: Any, usage: ((String) -> Void) -> Void) {

    switch error {
    case OptionParserError.multipleModesSpecified(let modes):
        print(error: error)

        if isTTY(.stdErr) && (modes.contains{ ["--help", "-h"].contains($0) }) {
            print("", to: &stderr)
            usage { print($0, to: &stderr) }
        }
    case OptionParserError.noCommandProvided(let hint):
        if !hint.isEmpty {
            print(error: error)
        }
        if isTTY(.stdErr) {
            usage { print($0, to: &stderr) }
        }
    case is OptionParserError:
        print(error: error)
        if isTTY(.stdErr) {
            let argv0 = Process.arguments.first ?? "swift package"
            print("enter `\(argv0) --help' for usage information", to: &stderr)
        }
    default:
        print(error: error)
    }

    exit(1)
}

private func print(error: Any) {
    if ColorWrap.isAllowed(for: .stdErr) {
        print(ColorWrap.wrap("error:", with: .Red, for: .stdErr), error, to: &stderr)
    } else {
        let cmd = Process.arguments.first?.basename ?? "SwiftPM"
        print("\(cmd): error:", error, to: &stderr)
    }
}
