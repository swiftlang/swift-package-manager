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
    stream <<< """
        #compdef swift
        local context state state_descr line
        typeset -A opt_args

        _swift() {
            _arguments -C \\
                '(- :)--help[prints the synopsis and a list of the most commonly used commands]: :->arg' \\
                '(-): :->command' \\
                '(-)*:: :->arg' && return

            case $state in
                (command)
                    local tools
                    tools=(
                        'build:build sources into binary products'
                        'run:build and run an executable product'
                        'package:perform operations on Swift packages'
                        'test:build and run tests'
                    )
                    _alternative \\
                        'tools:common:{_describe \"tool\" tools }' \\
                        'compiler: :_swift_compiler' && _ret=0
                    ;;
                (arg)
                    case ${words[1]} in
                        (build)
                            _swift_build
                            ;;
                        (run)
                            _swift_run
                            ;;
                        (package)
                            _swift_package
                            ;;
                        (test)
                            _swift_test
                            ;;
                        (*)
                            _swift_compiler
                            ;;
                    esac
                    ;;
            esac
        }

        _swift_dependency() {
            local dependencies
            dependencies=( $(\(listDependenciesCommand)) )
            _describe '' dependencies
        }

        _swift_executable() {
            local executables
            executables=( $(\(listExecutablesCommand)) )
            _describe '' executables
        }


        """


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
