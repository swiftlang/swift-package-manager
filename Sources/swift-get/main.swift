/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import dep
import POSIX
import sys

// Initialize the resource support.
public var globalSymbolInMainBinary = 0
Resources.initialize(&globalSymbolInMainBinary)

#if os(Linux)
    guard let locale = getenv("LC_ALL") ?? getenv("LC_CTYPE") ?? getenv("LANG") else {
        die("Error: Could not detect the environment’s locale, please set LANG")
    }
    guard locale.hasSuffix(".UTF-8") else {
        die("Error: `swift-get` requires the environment locale to be UTF-8 (\(locale))")
        // sorry about this, but Swift operates with UTF8 only and 
        // we are not yet sure how to embrace other 8-bit locales.
        // matters because: filename encodings
    }
#endif


//TODO warn if too restrictive a umask is set

let args = [String](Process.arguments.dropFirst())

do {
    try opendir(".")  // keep the working directory around for the duration of our process

    switch try CommandLine.parse(args) {
    case .Usage:
        usage()

    case .Version:
        print("swift-get 0.1")

    case .Install(let urls):
        let pkgs = try get(urls, prefix: try getcwd())
        for pkg in pkgs {
            try llbuild(srcroot: pkg.path, targets: try pkg.targets(), dependencies: pkgs, prefix: pkg.path, tmpdir: "\(pkg.path)/.build")
        }
    }

    exit(0)

} catch Error.InvalidUsage {
    if args.isEmpty {
        print("`swift get` allows you to fetch, update and use remote packages.", toStream: &stderr)
        print("", toStream: &stderr)
        usage()
    } else {
        print("Invalid usage", terminator: "", toStream: &stderr)
        if !attachedToTerminal() {
            print(": \(Process.prettyArguments)", toStream: &stderr)
        } else {
            print(". Enter `swift get --help` for usage information.", toStream: &stderr)
        }
    }

} catch let error as SystemError {
    print("System call error: \(error)", toStream: &stderr)
} catch {
    print("Unexpected error:", error, toStream: &stderr)
}

exit(1)
