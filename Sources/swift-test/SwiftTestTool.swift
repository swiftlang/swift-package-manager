/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.NSProcessInfo

import Basic
import Multitool
import Utility

import func POSIX.chdir
import func libc.exit

private enum Error: ErrorProtocol {
    case TestsExecutableNotFound
}

extension Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .TestsExecutableNotFound:
            return "no tests found to execute, create a module in your `Tests' directory"
        }
    }
}

private enum Mode: Argument, Equatable, CustomStringConvertible {
    case Usage
    case Run(String?)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--help", "--usage", "-h":
            self = .Usage
        case "-s":
            guard let specifier = pop() else { throw OptionParserError.ExpectedAssociatedValue(argument) }
            self = .Run(specifier)
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .Usage:
            return "--help"
        case .Run(let specifier):
            return specifier ?? ""
        }
    }
}

private func ==(lhs: Mode, rhs: Mode) -> Bool {
    return lhs.description == rhs.description
}

private enum Flag: Argument {
    case chdir(String)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--chdir", "-C":
            guard let path = pop() else { throw OptionParserError.ExpectedAssociatedValue(argument) }
            self = .chdir(path)
        default:
            return nil
        }
    }
}

/// swift-test tool namespace
struct SwiftTestTool {
    let args: [String]

    func run() {
        do {
            let (mode, opts) = try parseOptions(commandLineArguments: args)
        
            if let dir = opts.chdir {
                try chdir(dir)
            }
        
            switch mode {
            case .Usage:
                usage()
        
            case .Run(let specifier):
                let configuration = "debug"  //FIXME should swift-test support configuration option?
        
                func determineTestPath() throws -> String {
        
                    //FIXME better, ideally without parsing manifest since
                    // that makes us depend on the whole Manifest system
        
                    let packageName = opts.path.root.basename  //FIXME probably not true
                    let maybePath = Path.join(opts.path.build, configuration, "\(packageName)Tests.xctest")
        
                    if maybePath.exists {
                        return maybePath
                    } else {
                        let possiblePaths = walk(opts.path.build).filter {
                            $0.basename != "Package.xctest" &&   // this was our hardcoded name, may still exist if no clean
                            $0.hasSuffix(".xctest")
                        }
                        
                        guard let path = possiblePaths.first else {
                            throw Error.TestsExecutableNotFound
                        }
                        
                        return path
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
    }
    
    private func usage(_ print: (String) -> Void = { print($0) }) {
        //     .........10.........20.........30.........40.........50.........60.........70..
        print("OVERVIEW: Build and run tests")
        print("")
        print("USAGE: swift test [specifier] [options]")
        print("")
        print("SPECIFIER:")
        print("  -s TestModule.TestCase         Run a test case subclass")
        print("  -s TestModule.TestCase/test1   Run a specific test method")
        print("")
        print("OPTIONS:")
        print("  --chdir              Change working directory before any other operation [-C]")
        print("  --build-path <path>  Specify build directory")
    }

    private func parseOptions(commandLineArguments args: [String]) throws -> (Mode, Options) {
        let (mode, flags): (Mode?, [Flag]) = try Basic.parseOptions(arguments: args)

        let opts = Options()
        for flag in flags {
            switch flag {
            case .chdir(let path):
                opts.chdir = path
            }
        }

        return (mode ?? .Run(nil), opts)
    }

    private func test(path: String, xctestArg: String? = nil) throws -> Bool {
        guard path.isValidTest else {
            throw Error.TestsExecutableNotFound
        }

        var args: [String] = []
#if os(OSX)
        args = ["xcrun", "xctest"]
        if let xctestArg = xctestArg {
            args += ["-XCTest", xctestArg]
        }
        args += [path]
#else
        args += [path]
        if let xctestArg = xctestArg {
            args += [xctestArg]
        }
#endif

        // Execute the XCTest with inherited environment as it is convenient to pass senstive
        // information like username, password etc to test cases via enviornment variables.
        let result: Void? = try? system(args, environment: NSProcessInfo.processInfo().environment)
        return result != nil
    }
}

private extension String {
    var isValidTest: Bool {
        #if os(OSX)
            return isDirectory  // ${foo}.xctest is dir on OSX
        #else
            return isFile       // otherwise ${foo}.xctest is executable file
        #endif
    }
}
