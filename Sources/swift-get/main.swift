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
        print("Error: Could not detect the environment’s locale, please set LANG", toStream: &stderr)
    }
    guard locale.hasSuffix(".UTF-8") else {
        print("Error: `swift-get` requires the environment locale to be UTF-8 (\(locale))", toStream: &stderr)
        // sorry about this, but Swift operates with UTF8 only and 
        // we are not yet sure how to embrace other 8-bit locales.
        // matters because: filename encodings
    }
#endif


//TODO warn if too restrictive a umask is set

do {
    let args = Array(Process.arguments.dropFirst())
    let (mode, chdir, verbosity) = try parse(commandLineArguments: args)

    sys.verbosity = Verbosity(rawValue: verbosity)

    if let dir = chdir {
        try POSIX.chdir(dir)
    }

    // keep the working directory around for the duration of our process
    try opendir(".")

    switch mode {
    case .Usage:
        usage()

    case .Version:
        print("Apple Swift Package Manager 0.1")

    case .Install(let urls):
        let pkgs = try get(urls, prefix: try getcwd())
        for pkg in pkgs {
            try llbuild(srcroot: pkg.path, targets: try pkg.targets(), dependencies: pkgs, prefix: pkg.path, tmpdir: "\(pkg.path)/.build")
        }
    }

} catch CommandLineError.InvalidUsage(let hint, let mode) {

    print("Invalid usage: \(hint)", toStream: &stderr)

    if attachedToTerminal() {
        switch mode {
        case .Imply:
            print("Enter `swift get --help` for usage information.", toStream: &stderr)
        case .Print:
            print("", toStream: &stderr)
            usage { print($0, toStream: &stderr) }
        }
    }

    exit(1)

} catch {
    print("swift-get: \(error)", toStream: &stderr)
    exit(1)
}
