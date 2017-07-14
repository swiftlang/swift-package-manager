/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

/// Describes a tool which can be understood by llbuild's BuildSystem library.
protocol ToolProtocol {
    /// The list of inputs to declare.
    var inputs: [String] { get }

    /// The list of outputs to declare.
    var outputs: [String] { get }

    /// Write a description of the tool to the given output `stream`.
    ///
    /// This should append JSON or YAML content; if it is YAML it should be indented by 4 spaces.
    func append(to stream: OutputByteStream)
}

struct ShellTool: ToolProtocol {
    let description: String
    let inputs: [String]
    let outputs: [String]
    let args: [String]

    func append(to stream: OutputByteStream) {
        stream <<< "    tool: shell\n"
        stream <<< "    description: " <<< Format.asJSON(description) <<< "\n"
        stream <<< "    inputs: " <<< Format.asJSON(inputs) <<< "\n"
        stream <<< "    outputs: " <<< Format.asJSON(outputs) <<< "\n"

        // If one argument is specified we assume pre-escaped and have llbuild
        // execute it passed through to the shell.
        if let arg = self.args.only {
            stream <<< "    args: " <<< Format.asJSON(arg) <<< "\n"
        } else {
            stream <<< "    args: " <<< Format.asJSON(args) <<< "\n"
        }
    }
}

struct ClangTool: ToolProtocol {
    let desc: String
    let inputs: [String]
    let outputs: [String]
    let args: [String]
    let deps: String?

    func append(to stream: OutputByteStream) {
        stream <<< "    tool: clang\n"
        stream <<< "    description: " <<< Format.asJSON(desc) <<< "\n"
        stream <<< "    inputs: " <<< Format.asJSON(inputs) <<< "\n"
        stream <<< "    outputs: " <<< Format.asJSON(outputs) <<< "\n"
        stream <<< "    args: " <<< Format.asJSON(args) <<< "\n"
        if let deps = deps {
            stream <<< "    deps: " <<< Format.asJSON(deps) <<< "\n"
        }
    }
}

struct ArchiveTool: ToolProtocol {
    let inputs: [String]
    let outputs: [String]

    func append(to stream: OutputByteStream) {
        stream <<< "    tool: archive\n"
        stream <<< "    inputs: " <<< Format.asJSON(inputs) <<< "\n"
        stream <<< "    outputs: " <<< Format.asJSON(outputs) <<< "\n"
    }
}

/// Swift compiler llbuild tool.
struct SwiftCompilerTool: ToolProtocol {

    /// Inputs to the tool.
    let inputs: [String]

    /// Outputs produced by the tool.
    var outputs: [String] {
        return target.objects.map({ $0.asString }) + [target.moduleOutputPath.asString]
    }

    /// The underlying Swift build target.
    let target: SwiftTargetDescription

    static let numThreads = 8

    init(target: SwiftTargetDescription, inputs: [String]) {
        self.target = target
        self.inputs = inputs
    }

    func append(to stream: OutputByteStream) {
        stream <<< "    tool: swift-compiler\n"
        stream <<< "    executable: "
            <<< Format.asJSON(target.buildParameters.toolchain.swiftCompiler.asString) <<< "\n"
        stream <<< "    module-name: "
            <<< Format.asJSON(target.target.c99name) <<< "\n"
        stream <<< "    module-output-path: "
            <<< Format.asJSON(target.moduleOutputPath.asString) <<< "\n"
        stream <<< "    inputs: "
            <<< Format.asJSON(inputs) <<< "\n"
        stream <<< "    outputs: "
            <<< Format.asJSON(outputs) <<< "\n"
        stream <<< "    import-paths: "
            <<< Format.asJSON([target.buildParameters.buildPath.asString]) <<< "\n"
        stream <<< "    temps-path: "
            <<< Format.asJSON(target.tempsPath.asString) <<< "\n"
        stream <<< "    objects: "
            <<< Format.asJSON(target.objects.map({ $0.asString })) <<< "\n"
        stream <<< "    other-args: "
            <<< Format.asJSON(target.compileArguments()) <<< "\n"
        stream <<< "    sources: "
            <<< Format.asJSON(target.target.sources.paths.map({ $0.asString })) <<< "\n"
        stream <<< "    is-library: "
            <<< Format.asJSON(target.target.type == .library || target.target.type == .test) <<< "\n"
        stream <<< "    enable-whole-module-optimization: "
            <<< Format.asJSON(target.buildParameters.configuration == .release) <<< "\n"
        stream <<< "    num-threads: "
            <<< Format.asJSON("\(SwiftCompilerTool.numThreads)") <<< "\n"
    }
}
