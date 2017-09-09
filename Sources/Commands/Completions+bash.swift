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

let listDependenciesCommand = "swift package \(PackageMode.completionTool.rawValue) \(PackageToolOptions.CompletionToolMode.listDependencies.rawValue)"
let listExecutablesCommand = "swift package \(PackageMode.completionTool.rawValue) \(PackageToolOptions.CompletionToolMode.listExecutables.rawValue)"

/// Template for Bash completion script.
///
/// - Parameter stream: output stream to write the script to.
func bash_template(on stream: OutputByteStream) {
    stream <<< """
        #!/bin/bash

        _swift()
        {
            declare -a cur prev

        """

    // Setup `cur` and `prev` variables, these will be used in the various
    // functions this script will contain. For example if the user requests
    // completions for `swift pack⇥`, `$cur` is `pack` and `$prev` is `swift`.
    stream <<< """
            cur=\"${COMP_WORDS[COMP_CWORD]}\"
            prev=\"${COMP_WORDS[COMP_CWORD-1]}\"

            COMPREPLY=()

        """

    // If we're on the second completion word: `swift #`, then we'll complete
    // the names of the tools and compiler flags.
    stream <<< """
            if [[ $COMP_CWORD == 1 ]]; then
                _swift_compiler
                COMPREPLY+=( $(compgen -W \"build run package test\" -- $cur) )
                return
            fi

        """

    // For subsequent words; we'll look at the second word.  In all other
    // cases, try to complete compiler flags.
    stream <<< "    case ${COMP_WORDS[1]} in\n"

    // If it is a tool name, forward completion to the specific tool's completion.
    stream <<< """
                (build)
                    _swift_build 2
                    ;;
                (run)
                    _swift_run 2
                    ;;
                (package)
                    _swift_package 2
                    ;;
                (test)
                    _swift_test 2
                    ;;

        """

    // Otherwise; forward completion to the compiler's completion.
    stream <<< """
                (*)
                    _swift_compiler
                    ;;
            esac
        }

        _swift_dependency() {
            COMPREPLY=( $(compgen -W "$(\(listDependenciesCommand))" -- $cur) )
        }

        _swift_executable() {
            COMPREPLY=( $(compgen -W "$(\(listExecutablesCommand))" -- $cur) )
        }


        """

    SwiftBuildTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftRunTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftPackageTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftTestTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)

    // Forward to swift compiler completion, if defined.
    stream <<< """
        _swift_compiler()
        {
            if [[ `type -t _swift_complete`"" == 'function' ]]; then
                _swift_complete
            fi
        }


        """

    // Link the `_swift` function to the `swift` command.
    stream <<< "complete -F _swift swift\n"

    stream.flush()
}
