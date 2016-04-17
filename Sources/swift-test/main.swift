/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.chdir
import func libc.exit
import Multitool
import Utility

do {
    let args = Array(Process.arguments.dropFirst())
    let (mode, opts) = try parse(commandLineArguments: args)

    if let dir = opts.chdir {
        try chdir(dir)
    }

    switch mode {
    case .Usage:
        usage()

    case .Run(let specifier):
        let configuration = "debug"  //FIXME should swift-test support configuration option?

        func determineTestPath() -> String {

            //FIXME better, ideally without parsing manifest since
            // that makes us depend on the whole Manifest system

            let packageName = opts.path.root.basename  //FIXME probably not true
            let maybePath = Path.join(opts.path.build, configuration, "\(packageName).xctest")

            if maybePath.exists {
                return maybePath
            } else {
                return walk(opts.path.build).filter {
                    $0.basename != "Package.xctest" &&   // this was our hardcoded name, may still exist if no clean
                    $0.hasSuffix(".xctest")
                }.first!
            }
        }

        let yamlPath = Path.join(opts.path.build, "\(configuration).yaml")
        try build(YAMLPath: yamlPath, target: "test")
        let success = try test(path: determineTestPath(), xctestArg: specifier)
        exit(success ? 0 : 1)
    }
} catch Multitool.Error.BuildYAMLNotFound {
    print("error: you must run `swift build` first", to: &stderr)
    exit(1)
} catch {
    handle(error: error, usage: usage)
}
