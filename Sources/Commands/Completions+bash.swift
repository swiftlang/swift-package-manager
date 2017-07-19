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

/// Template for Bash completion script.
///
/// - Parameter stream: output stream to write the script to.
func bash_template(on stream: OutputByteStream) {
    stream <<< "#!/bin/bash\n"

    stream <<< "_swift() \n"
    stream <<< "{\n"
    stream <<< "    declare -a cur prev\n"

    // Setup `cur` and `prev` variables, these will be used in the various
    // functions this script will contain. For example if the user requests
    // completions for `swift pack⇥`, `$cur` is `pack` and `$prev` is `swift`.
    stream <<< "    cur=\"${COMP_WORDS[COMP_CWORD]}\"\n"
    stream <<< "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n"

    stream <<< "    COMPREPLY=()\n"

    // If we're on the second completion word: `swift #`, then we'll complete
    // the names of the tools and compiler flags.
    stream <<< "    if [[ $COMP_CWORD == 1 ]]; then\n"
    stream <<< "        COMPREPLY=( $(compgen -W \"build run package test\" -- $cur) )\n"
    stream <<< "        _swift_compiler\n"
    stream <<< "        return\n"
    stream <<< "    fi\n"

    // For subsequent words; we'll look at the second word.  In all other
    // cases, try to complete compiler flags.
    stream <<< "    case ${COMP_WORDS[1]} in\n"

    // If it is a tool name, forward completion to the specific tool's completion.
    stream <<< "        (build)\n"
    stream <<< "            _swift_build 2\n"
    stream <<< "            ;;\n"
    stream <<< "        (run)\n"
    stream <<< "            _swift_run 2\n"
    stream <<< "            ;;\n"
    stream <<< "        (package)\n"
    stream <<< "            _swift_package 2\n"
    stream <<< "            ;;\n"
    stream <<< "        (test)\n"
    stream <<< "            _swift_test 2\n"
    stream <<< "            ;;\n"

    // Otherwise; forward completion to the compiler's completion.
    stream <<< "        (*)\n"
    stream <<< "            _swift_compiler\n"
    stream <<< "            ;;\n"
    stream <<< "    esac\n"
    stream <<< "}\n"

    SwiftBuildTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftRunTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftPackageTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftTestTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)

    // Figure out how to forward to swift compiler's bash completion.
    stream <<< """
               _swift_compiler()
               {
                   return 0
               }


               """

    // Link the `_swift` function to the `swift` command.
    stream <<< "complete -F _swift swift\n"

    stream.flush()
}
