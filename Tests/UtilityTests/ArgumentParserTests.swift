/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Basic
import TestSupport
import Utility

enum SampleEnum: String {
    case Foo
    case Bar
}

extension SampleEnum: StringEnumArgument {
    static var completion: ShellCompletion {
        return .values([
            (SampleEnum.Foo.rawValue, ""),
            (SampleEnum.Bar.rawValue, "")
        ])
    }
}

struct Options {
    struct Flags {
        let xswiftc: [String]
        let xlinker: [String]
    }
    var branch: String?
    var package: String!
    var isVerbose: Bool = false
    var xld = [String]()
    var flags = Flags(xswiftc: [], xlinker: [])
    var foo: String?
    var bar: Int?
}

class ArgumentParserTests: XCTestCase {

    func testBasics() throws {
        let parser = ArgumentParser(commandName:"SomeBinary", usage: "sample parser", overview: "Sample overview")

        let package = parser.add(positional: "package name of the year", kind: String.self, usage: "The name of the package")
        let revision = parser.add(option: "--revision", kind: String.self, usage: "The revision")
        let branch = parser.add(option: "--branch", shortName:"-b", kind: String.self, usage: "The branch to checkout")
        let xld = parser.add(option: "-Xld", kind: [String].self, strategy: .oneByOne, usage: "The xld arguments")
        let verbosity = parser.add(option: "--verbose", kind: Int.self, usage: "The verbosity level")
        let noFly = parser.add(option: "--no-fly", kind: Bool.self, usage: "If should fly")
        let sampleEnum = parser.add(positional: "enum", kind: SampleEnum.self)
        let foo = parser.add(option: "--foo", kind: String.self)
        let inputFiles = parser.add(positional: "input files", kind: [String].self, usage: "A list of input files")
        let outputFiles = parser.add(option: "--output-files", kind: [String].self, usage: "A list of output files")
        let remaining = parser.add(option: "--remaining", kind: [String].self, strategy: .remaining, usage: "Remaining arguments")
        
        let args = try parser.parse([
            "Foo",
            "-b", "bugfix",
            "--verbose", "2",
            "-Xld", "-Lfoo",
            "-Xld", "-Lbar",
            "--no-fly",
            "Bar",
            "--foo=bar",
            "input1", "input2",
            "--output-files", "output1", "output2",
            "--remaining", "--foo", "-Xld", "bar"])

        XCTAssertEqual(args.get(package), "Foo")
        XCTAssert(args.get(revision) == nil)
        XCTAssertEqual(args.get(branch), "bugfix")
        XCTAssertEqual(args.get(xld) ?? [], ["-Lfoo", "-Lbar"])
        XCTAssertEqual(args.get(verbosity), 2)
        XCTAssertEqual(args.get(noFly), true)
        XCTAssertEqual(args.get(sampleEnum), .Bar)
        XCTAssertEqual(args.get(foo), "bar")
        XCTAssertEqual(args.get(inputFiles) ?? [], ["input1", "input2"])
        XCTAssertEqual(args.get(outputFiles) ?? [], ["output1", "output2"])
        XCTAssertEqual(args.get(remaining) ?? [], ["--foo", "-Xld", "bar"])

        let stream = BufferedOutputByteStream()
        parser.printUsage(on: stream)
        let usage = stream.bytes.asString!
        XCTAssert(usage.contains("OVERVIEW: Sample overview"))
        XCTAssert(usage.contains("USAGE: SomeBinary sample parser"))
        XCTAssert(usage.contains("  package name of the year\n                          The name of the package"))
        XCTAssert(usage.contains(" -Xld                    The xld arguments"))
        XCTAssert(usage.contains("--help"))
    }

    func testErrors() throws {
        let parser = ArgumentParser(usage: "sample", overview: "sample")
        _ = parser.add(positional: "package", kind: String.self, usage: "The name of the package")
        _ = parser.add(option: "--verbosity", kind: Int.self, usage: "The revision")
        _ = parser.add(option: "--foo", kind: Bool.self)

        do {
            _ = try parser.parse()
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedArguments(let p, let args) {
            XCTAssert(p === parser)
            XCTAssertEqual(args, ["package"])
        }

        do {
            _ = try parser.parse(["foo", "bar"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unexpectedArgument(let arg) {
            XCTAssertEqual(arg, "bar")
        }

        do {
            _ = try parser.parse(["foo", "--bar"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unknownOption(let option) {
            XCTAssertEqual(option, "--bar")
        }

        do {
            _ = try parser.parse(["foo", "--verbosity"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedValue(let option) {
            XCTAssertEqual(option, "--verbosity")
        }

        do {
            _ = try parser.parse(["foo", "--verbosity", "yes"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.invalidValue(let option, let error) {
            XCTAssertEqual(option, "--verbosity")
            XCTAssertEqual(error, ArgumentConversionError.typeMismatch(value: "yes", expectedType: Int.self))
        }

        do {
            _ = try parser.parse(["foo", "--foo=hello"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.invalidValue(let option, let error) {
            XCTAssertEqual(option, "--foo")
            XCTAssertEqual(error, ArgumentConversionError.unknown(value: "hello"))
        }
    }

    func testOptions() throws {
        let parser = ArgumentParser(usage: "sample parser", overview: "Sample overview")
        let binder = ArgumentBinder<Options>()

        binder.bind(
            positional: parser.add(positional: "package", kind: String.self),
            to: { $0.package = $1 })

        binder.bindPositional(
            parser.add(positional: "foo", kind: String.self),
            parser.add(positional: "bar", kind: Int.self),
            to: { 
                $0.foo = $1
                $0.bar = $2
            })

        binder.bind(
            option: parser.add(option: "--branch", shortName:"-b", kind: String.self),
            to: { $0.branch = $1 })

        binder.bind(
            option: parser.add(option: "--verbose", kind: Bool.self),
            to: { $0.isVerbose = $1 })

        binder.bindArray(
            option: parser.add(option: "-Xld", kind: Array<String>.self),
            to: { $0.xld = $1 })

        binder.bindArray(
            parser.add(option: "-xlinker", kind: [String].self),
            parser.add(option: "-xswiftc", kind: [String].self),
            to: { $0.flags = Options.Flags(xswiftc: $2, xlinker: $1) })

        let result = try parser.parse(["MyPkg", "foo", "3", "-b", "bugfix", "--verbose", "-Xld", "foo", "-Xld", "bar", "-xlinker", "a", "-xswiftc", "b"])

        var options = Options()
        binder.fill(result, into: &options)

        XCTAssertEqual(options.branch, "bugfix")
        XCTAssertEqual(options.package, "MyPkg")
        XCTAssertEqual(options.isVerbose, true)
        XCTAssertEqual(options.xld, ["foo", "bar"])
        XCTAssertEqual(options.flags.xlinker, ["a"])
        XCTAssertEqual(options.flags.xswiftc, ["b"])
        XCTAssertEqual(options.foo, "foo")
        XCTAssertEqual(options.bar, 3)
    }

    func testSubparser() throws {
        let parser = ArgumentParser(commandName: "SomeBinary", usage: "sample parser", overview: "Sample overview")
        let foo = parser.add(option: "--foo", kind: String.self, usage: "The foo option")

        let parserA = parser.add(subparser: "a", overview: "A!")
        let branchOption = parserA.add(option: "--branch", kind: String.self, usage: "The branch to use")

        let parserB = parser.add(subparser: "b", overview: "B!")
        let noFlyOption = parserB.add(option: "--no-fly", kind: Bool.self, usage: "Should you fly?")

        var args = try parser.parse(["--foo", "foo", "a", "--branch", "bugfix"])
        XCTAssertEqual(args.get(foo), "foo")
        XCTAssertEqual(args.get(branchOption), "bugfix")
        XCTAssertEqual(args.get(noFlyOption), nil)
        XCTAssertEqual(args.subparser(parser), "a")

        args = try parser.parse(["--foo", "foo", "b", "--no-fly"])

        XCTAssertEqual(args.get(foo), "foo")
        XCTAssertEqual(args.get(branchOption), nil)
        XCTAssertEqual(args.get(noFlyOption), true)
        XCTAssertEqual(args.subparser(parser), "b")

        do {
            args = try parser.parse(["c"])
        } catch ArgumentParserError.expectedArguments(_, let args) {
            XCTAssertEqual(args.sorted(), ["a", "b"])
        }

        do {
            args = try parser.parse(["--foo", "foo", "b", "--no-fly", "--branch", "bugfix"])
        } catch ArgumentParserError.unknownOption(let arg) {
            XCTAssertEqual(arg, "--branch")
        }

        do {
            args = try parser.parse(["--foo", "foo", "a", "--branch", "bugfix", "--no-fly"])
        } catch ArgumentParserError.unknownOption(let arg) {
            XCTAssertEqual(arg, "--no-fly")
        }

        do {
            args = try parser.parse(["a", "--branch", "bugfix", "--foo"])
        } catch ArgumentParserError.unknownOption(let arg) {
            XCTAssertEqual(arg, "--foo")
        }

        var stream = BufferedOutputByteStream()
        parser.printUsage(on: stream)
        var usage = stream.bytes.asString!

        XCTAssert(usage.contains("OVERVIEW: Sample overview"))
        XCTAssert(usage.contains("USAGE: SomeBinary sample parser"))
        XCTAssert(usage.contains("  --foo   The foo option"))
        XCTAssert(usage.contains("SUBCOMMANDS:"))
        XCTAssert(usage.contains("  b       B!"))
        XCTAssert(usage.contains("--help"))

        stream = BufferedOutputByteStream()
        parserA.printUsage(on: stream)
        usage = stream.bytes.asString!

        XCTAssert(usage.contains("OVERVIEW: A!"))
        XCTAssert(!usage.contains("USAGE:"))
        XCTAssert(usage.contains("OPTIONS:"))
        XCTAssert(usage.contains("  --branch   The branch to use"))
        XCTAssertFalse(usage.contains("--help"))

        stream = BufferedOutputByteStream()
        parserB.printUsage(on: stream)
        usage = stream.bytes.asString!

        XCTAssert(usage.contains("OVERVIEW: B!"))
        XCTAssert(!usage.contains("USAGE:"))
        XCTAssert(usage.contains("OPTIONS:"))
        XCTAssert(usage.contains("  --no-fly"))
    }

    func testSubsubparser() throws {
        let parser = ArgumentParser(usage: "sample parser", overview: "Sample overview")

        let parserA = parser.add(subparser: "foo", overview: "A!")
        let branchOption = parserA.add(option: "--branch", kind: String.self)

        _ = parserA.add(subparser: "bar", overview: "Bar!")
        let parserAB = parserA.add(subparser: "baz", overview: "Baz!")
        let noFlyOption = parserAB.add(option: "--no-fly", kind: Bool.self)

        var args = try parser.parse(["foo", "--branch", "bugfix", "baz", "--no-fly"])

        XCTAssertEqual(args.get(branchOption), "bugfix")
        XCTAssertEqual(args.get(noFlyOption), true)
        XCTAssertEqual(args.subparser(parserA), "baz")
        XCTAssertEqual(args.subparser(parser), "foo")

        args = try parser.parse(["foo", "bar"])

        XCTAssertEqual(args.get(branchOption), nil)
        XCTAssertEqual(args.get(noFlyOption), nil)
        XCTAssertEqual(args.subparser(parserA), "bar")
        XCTAssertEqual(args.subparser(parser), "foo")

        do {
            args = try parser.parse(["c"])
        } catch ArgumentParserError.expectedArguments(_, let args) {
            XCTAssertEqual(args.sorted(), ["foo"])
        }

        do {
            args = try parser.parse(["foo", "--branch", "b", "foo"])
        } catch ArgumentParserError.expectedArguments(_, let args) {
            XCTAssertEqual(args.sorted(), ["bar", "baz"])
        }

        do {
            args = try parser.parse(["foo", "bar", "--no-fly"])
        } catch ArgumentParserError.unknownOption(let arg) {
            XCTAssertEqual(arg, "--no-fly")
        }
    }

    func testSubparserBinder() throws {

        struct Options {
            enum Mode: String {
                case update
                case fetch
            }
            var mode: Mode = .update
            var branch: String?
        }

        let parser = ArgumentParser(usage: "sample parser", overview: "Sample overview")
        let binder = ArgumentBinder<Options>()

        binder.bind(
            option: parser.add(option: "--branch", shortName: "-b", kind: String.self),
            to: { $0.branch = $1 })

        _ = parser.add(subparser: "init", overview: "A!")
        _ = parser.add(subparser: "fetch", overview: "B!")

        binder.bind(
            parser: parser,
            to: { $0.mode = Options.Mode(rawValue: $1)! })

        let result = try parser.parse(["--branch", "ok", "fetch"])

        var options = Options()
        binder.fill(result, into: &options)

        XCTAssertEqual(options.branch, "ok")
        XCTAssertEqual(options.mode, .fetch)
    }

    func testOptionalPositionalArg() throws {
        let parser = ArgumentParser(commandName:"SomeBinary", usage: "sample parser", overview: "Sample overview")

        let package = parser.add(positional: "package name of the year", kind: String.self, optional: true, usage: "The name of the package")
        let revision = parser.add(option: "--revision", kind: String.self, usage: "The revision")

        do {
            let args = try parser.parse(["Foo", "--revision", "bugfix"])
            XCTAssertEqual(args.get(package), "Foo")
            XCTAssertEqual(args.get(revision), "bugfix")
        }

        do {
            let args = try parser.parse(["--revision", "bugfix"])
            XCTAssertEqual(args.get(package), nil)
            XCTAssertEqual(args.get(revision), "bugfix")
        }

        struct Options {
            var package: String?
            var revision: String?
        }
        let binder = ArgumentBinder<Options>()

        binder.bind(
            positional: package,
            to: { $0.package = $1 })
        binder.bind(
            option: revision,
            to: { $0.revision = $1 })

        do {
            let result = try parser.parse(["Foo", "--revision", "bugfix"])
            var options = Options()
            binder.fill(result, into: &options)
            XCTAssertEqual(options.package, "Foo")
            XCTAssertEqual(options.revision, "bugfix")
        }

        do {
            let result = try parser.parse(["--revision", "bugfix"])
            var options = Options()
            binder.fill(result, into: &options)
            XCTAssertEqual(options.package, nil)
            XCTAssertEqual(options.revision, "bugfix")
        }
    }

    func testPathArgument() {
        // Test that relative path is resolved.
        do {
            let actual = try! SwiftPMProduct.TestSupportExecutable.execute(["pathArgumentTest", "some/path"]).chomp()
            let expected = currentWorkingDirectory.appending(RelativePath("some/path")).asString
            XCTAssertEqual(actual, expected)
        }

        // Test that relative path starting with ./ is resolved.
        do {
            let actual = try! SwiftPMProduct.TestSupportExecutable.execute(["pathArgumentTest", "./some/path"]).chomp()
            let expected = currentWorkingDirectory.appending(RelativePath("./some/path")).asString
            XCTAssertEqual(actual, expected)
        }

        // Test that relative path starting with ../ is resolved.
        do {
            let actual = try! SwiftPMProduct.TestSupportExecutable.execute(["pathArgumentTest", "../other/path"]).chomp()
            let expected = currentWorkingDirectory.appending(RelativePath("../other/path")).asString
            XCTAssertEqual(actual, expected)
        }

        // Test that absolute path is resolved.
        do {
            let actual = try! SwiftPMProduct.TestSupportExecutable.execute(["pathArgumentTest", "/bin/echo"]).chomp()
            XCTAssertEqual(actual, "/bin/echo")
        }
    }

    func testShellCompletionGeneration() throws {
        let parser = ArgumentParser(commandName:"SomeBinary", usage: "sample parser", overview: "Sample overview")

        _ = parser.add(positional: "package name of the year", kind: String.self, optional: true, usage: "The name of the package")
        _ = parser.add(option: "--revision", kind: String.self, usage: "The revision")

        var output = BufferedOutputByteStream()
        parser.generateCompletionScript(for: .bash, on: output)
        XCTAssertEqual(output.bytes, ByteString(encodingAsUTF8: [
            "# Generates completions for SomeBinary",
            "#",
            "# Parameters",
            "# - the start position of this parser; set to 1 if unknown",
            "function _SomeBinary",
            "{",
            "    if [[ $COMP_CWORD == $(($1+0)) ]]; then",
            "            return",
            "    fi",
            "    if [[ $COMP_CWORD == $1 ]]; then",
            "        COMPREPLY=( $(compgen -W \"--revision\" -- $cur) )",
            "        return",
            "    fi",
            "    case $prev in",
            "        (--revision)",
            "            return",
            "        ;;",
            "    esac",
            "    case ${COMP_WORDS[$1]} in",
            "    esac",
            "    COMPREPLY=( $(compgen -W \"--revision\" -- $cur) )",
            "}",
            "",
            ""].joined(separator: "\n")))

        output = BufferedOutputByteStream()
        parser.generateCompletionScript(for: .zsh, on: output)
        XCTAssertEqual(output.bytes, ByteString(encodingAsUTF8: [
            "# Generates completions for SomeBinary",
            "#",
            "# In the final compdef file, set the following file header:",
            "#",
            "#     #compdef _SomeBinary",
            "#     local context state state_descr line",
            "#     typeset -A opt_args",
            "_SomeBinary() {",
            "    arguments=(",
            "        \":The name of the package: \"",
            "        \"--revision[The revision]:The revision: \"",
            "    )",
            "    _arguments $arguments && return",
            "}",
            "",
            ""].joined(separator: "\n")))
    }

    func testUpToNextOptionStrategy() throws {
        let parser = ArgumentParser(commandName: "SomeBinary", usage: "sample parser", overview: "Sample overview")

        let option1 = parser.add(option: "--opt1", kind: [String].self)
        let option2 = parser.add(option: "--opt2", kind: [String].self)
        let positional = parser.add(positional: "positional", kind: [String].self, optional: true)

        var args = try parser.parse(["--opt1", "val11", "val12", "--opt2", "val21"])

        XCTAssertEqual(args.get(option1) ?? [], ["val11", "val12"])
        XCTAssertEqual(args.get(option2) ?? [], ["val21"])
        XCTAssertNil(args.get(positional))

        args = try parser.parse(["posi1", "posi2", "--opt1", "val11"])

        XCTAssertEqual(args.get(option1) ?? [], ["val11"])
        XCTAssertNil(args.get(option2))
        XCTAssertEqual(args.get(positional) ?? [], ["posi1", "posi2"])

        args = try parser.parse(["--opt1=val", "--opt2", "val2"])
        XCTAssertEqual(args.get(option1) ?? [], ["val"])
        XCTAssertEqual(args.get(option2) ?? [], ["val2"])
        XCTAssertNil(args.get(positional))

        args = try parser.parse(["--opt1=val", "posi"])
        XCTAssertEqual(args.get(option1) ?? [], ["val"])
        XCTAssertNil(args.get(option2))
        XCTAssertEqual(args.get(positional) ?? [], ["posi"])

        do {
            _ = try parser.parse(["--opt1", "--opt2", "val21"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedValue("--opt1") { }

        do {
            _ = try parser.parse(["--opt1", "val11", "--opt2"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedValue("--opt2") { }
    }

    func testRemainingStrategy() throws {
        let parser = ArgumentParser(commandName: "SomeBinary", usage: "sample parser", overview: "Sample overview")
        
        let option1 = parser.add(option: "--foo", kind: String.self)
        let option2 = parser.add(option: "--bar", kind: [String].self, strategy: .remaining)
        let positional = parser.add(positional: "executable", kind: [String].self, optional: true, strategy: .remaining)
        
        var args = try parser.parse([
            "--foo", "bar",
            "exe", "--with", "options", "--foo", "notbar"
        ])
        
        XCTAssertEqual(args.get(option1), "bar")
        XCTAssertNil(args.get(option2))
        XCTAssertEqual(args.get(positional) ?? [], ["exe", "--with", "options", "--foo", "notbar"])

        args = try parser.parse([
            "--foo", "bar",
            "--bar", "--with", "options", "--foo", "notbar"
        ])

        XCTAssertEqual(args.get(option1), "bar")
        XCTAssertEqual(args.get(option2) ?? [], ["--with", "options", "--foo", "notbar"])
        XCTAssertNil(args.get(positional))

        do {
            _ = try parser.parse(["--foo", "bar", "--bar"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedValue("--bar") { }
    }

    func testBoolParsing() throws {
        var parser = ArgumentParser(usage: "sample", overview: "sample")
        let option = parser.add(option: "--verbose", kind: Bool.self)

        do {
            _ = try parser.parse(["--verbose", "true"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unexpectedArgument(let argument) {
            XCTAssertEqual(argument, "true")
        }

        do {
            _ = try parser.parse(["--verbose=yes"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.invalidValue(let option, let error) {
            XCTAssertEqual(option, "--verbose")
            XCTAssertEqual(error, .unknown(value: "yes"))
        }

        var args = try parser.parse(["--verbose=true"])
        XCTAssertEqual(args.get(option), true)

        args = try parser.parse(["--verbose=false"])
        XCTAssertEqual(args.get(option), false)

        args = try parser.parse(["--verbose"])
        XCTAssertEqual(args.get(option), true)

        args = try parser.parse([])
        XCTAssertEqual(args.get(option), nil)

        parser = ArgumentParser(usage: "sample", overview: "sample")
        let positional = parser.add(positional: "posi", kind: Bool.self)

        do {
            _ = try parser.parse(["yes"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.invalidValue(let positional, let error) {
            XCTAssertEqual(positional, "posi")
            XCTAssertEqual(error, .unknown(value: "yes"))
        }

        args = try parser.parse(["true"])
        XCTAssertEqual(args.get(positional), true)

        args = try parser.parse(["false"])
        XCTAssertEqual(args.get(positional), false)
    }

    func testIntParsing() throws {
        var parser = ArgumentParser(usage: "sample", overview: "sample")
        let option = parser.add(option: "--verbosity", kind: Int.self)

        do {
            _ = try parser.parse(["--verbosity"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedValue(let option) {
            XCTAssertEqual(option, "--verbosity")
        }

        do {
            _ = try parser.parse(["--verbosity=4.5"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.invalidValue(let option, let error) {
            XCTAssertEqual(option, "--verbosity")
            XCTAssertEqual(error, .typeMismatch(value: "4.5", expectedType: Int.self))
        }

        do {
            _ = try parser.parse(["--verbosity", "notInt"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.invalidValue(let option, let error) {
            XCTAssertEqual(option, "--verbosity")
            XCTAssertEqual(error, .typeMismatch(value: "notInt", expectedType: Int.self))
        }

        var args = try parser.parse(["--verbosity=4"])
        XCTAssertEqual(args.get(option), 4)

        args = try parser.parse(["--verbosity", "-2"])
        XCTAssertEqual(args.get(option), -2)

        args = try parser.parse([])
        XCTAssertEqual(args.get(option), nil)

        parser = ArgumentParser(usage: "sample", overview: "sample")
        let positional = parser.add(positional: "posi", kind: Int.self)

        do {
            _ = try parser.parse(["yes"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.invalidValue(let positional, let error) {
            XCTAssertEqual(positional, "posi")
            XCTAssertEqual(error, .typeMismatch(value: "yes", expectedType: Int.self))
        }

        do {
            _ = try parser.parse(["-18"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unknownOption(let option) {
            XCTAssertEqual(option, "-18")
        }

        args = try parser.parse(["0"])
        XCTAssertEqual(args.get(positional), 0)
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testErrors", testErrors),
        ("testOptions", testOptions),
        ("testSubparser", testSubparser),
        ("testSubsubparser", testSubsubparser),
        ("testSubparserBinder", testSubparserBinder),
        ("testOptionalPositionalArg", testOptionalPositionalArg),
        ("testPathArgument", testPathArgument),
        ("testShellCompletionGeneration", testShellCompletionGeneration),
        ("testUpToNextOptionStrategy", testUpToNextOptionStrategy),
        ("testRemainingStrategy", testRemainingStrategy),
        ("testBoolParsing", testBoolParsing),
        ("testIntParsing", testIntParsing)
    ]
}
