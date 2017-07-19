/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Basic
import Utility

/// Template for ZSH completion script.
///
/// - Parameter stream: output stream to write the script to.
func zsh_template(on stream: OutputByteStream) {
    stream <<< "#compdef swift\n"
    stream <<< "local context state state_descr line\n"
    stream <<< "typeset -A opt_args\n"
    stream <<< "\n"
    stream <<< "_swift() {\n"
    stream <<< "    _arguments -C \\\n"
    stream <<< "        '(- :)--help[prints the synopsis and a list of the most commonly used commands]: :->arg' \\\n"
    stream <<< "        '(-): :->command' \\\n"
    stream <<< "        '(-)*:: :->arg' && return\n"
    stream <<< "\n"
    stream <<< "    case $state in\n"
    stream <<< "        (command)\n"
    stream <<< "            local tools\n"
    stream <<< "            tools=(\n"
    stream <<< "                'build:build sources into binary products'\n"
    stream <<< "                'run:build and run an executable product'\n"
    stream <<< "                'package:perform operations on Swift packages'\n"
    stream <<< "                'test:build and run tests'\n"
    stream <<< "            )\n"
    stream <<< "            _alternative \\\n"
    stream <<< "                'tools:common:{_describe \"tool\" tools }' \\\n"
    stream <<< "                'compiler: :_swift_compiler' && _ret=0\n"
    stream <<< "            ;;\n"
    stream <<< "        (arg)\n"
    stream <<< "            case ${words[1]} in\n"
    stream <<< "                (build)\n"
    stream <<< "                    _swift_build\n"
    stream <<< "                    ;;\n"
    stream <<< "                (run)\n"
    stream <<< "                    _swift_run\n"
    stream <<< "                    ;;\n"
    stream <<< "                (package)\n"
    stream <<< "                    _swift_package\n"
    stream <<< "                    ;;\n"
    stream <<< "                (test)\n"
    stream <<< "                    _swift_test\n"
    stream <<< "                    ;;\n"
    stream <<< "                (*)\n"
    stream <<< "                    _swift_compiler\n"
    stream <<< "                    ;;\n"
    stream <<< "            esac\n"
    stream <<< "            ;;\n"
    stream <<< "    esac\n"
    stream <<< "}\n"
    stream <<< "\n"

    SwiftBuildTool(args: []).parser.generateCompletionScript(for: .zsh, on: stream)
    SwiftRunTool(args: []).parser.generateCompletionScript(for: .zsh, on: stream)
    SwiftPackageTool(args: []).parser.generateCompletionScript(for: .zsh, on: stream)
    SwiftTestTool(args: []).parser.generateCompletionScript(for: .zsh, on: stream)

    // Figure out how to forward to swift compiler's bash completion.
    stream <<< """
               _swift_compiler() {
               }


               """

    // Run the `_swift` function to register the completions.
    stream <<< "_swift\n"

    stream.flush()
}
