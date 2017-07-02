//
//  bash_template.swift
//  SwiftPM
//
//  Created by Bouke Haarsma on 29/09/2016.
//
//

import Foundation
import Basic
import Utility

func bash_template(on stream: OutputByteStream) {
    stream <<< "#!/bin/bash\n"
    
    stream <<< "_swift() \n"
    stream <<< "{\n"
    stream <<< "    declare -a cur prev\n"
    stream <<< "    cur=\"${COMP_WORDS[COMP_CWORD]}\"\n"
    stream <<< "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n"
    
    stream <<< "    COMPREPLY=()\n"
    
    stream <<< "    # completions for tools, and compiler flags (non-tool)\n"
    stream <<< "    if [[ $COMP_CWORD == 1 ]]; then\n"
    stream <<< "        COMPREPLY=( $(compgen -W \"build run package test\" -- $cur) )\n"
    stream <<< "        _swift_compiler\n"
    stream <<< "        return\n"
    stream <<< "    fi\n"
    
    stream <<< "    # specify for each tool\n"
    stream <<< "    case ${COMP_WORDS[1]} in\n"
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
    stream <<< "        (*)\n"
    stream <<< "            _swift_compiler\n"
    stream <<< "            ;;\n"
    stream <<< "    esac\n"
    stream <<< "}\n"
    
    SwiftBuildTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftRunTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftPackageTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    SwiftTestTool(args: []).parser.generateCompletionScript(for: .bash, on: stream)
    
    stream <<< "_swift_compiler()\n"
    stream <<< "{\n"
    stream <<< "    case $prev in\n"
    stream <<< "        (-assert-config)\n"
    stream <<< "            COMPREPLY=( $(compgen -W \"Debug Release Unchecked DisableReplacement\" -- $cur) )\n"
    stream <<< "            return\n"
    stream <<< "            ;;\n"
    stream <<< "        (-D|-framework|-j|-l|-module-link-name|-module-name|-num-threads|-sdk|-target-cpu|-target|-use-ld)\n"
    stream <<< "            return\n"
    stream <<< "            ;;\n"
    stream <<< "        (-F|-index-store-path|-I|-L|-module-cache-path)\n"
    stream <<< "            _filedir\n"
    stream <<< "            ;;\n"
    stream <<< "    esac\n"
    stream <<< "    local args\n"
    stream <<< "    args=\"-assert-config -continue-building-after-errors -D -framework\\\n"
    stream <<< "         -F -gdwarf-types -gline-tables-only \\\n"
    stream <<< "         -gnone -g -help -index-store-path -I -j -L -l -module-cache-path \\\n"
    stream <<< "         -module-link-name -module-name -nostdimport -num-threads -Onone \\\n"
    stream <<< "         -Ounchecked -O -sdk -static-executable -static-stdlib -suppress-warnings \\\n"
    stream <<< "         -target-cpu \\\n"
    stream <<< "         -target -use-ld -version -v -warn-swift3-objc-inference-complete \\\n"
    stream <<< "         -warn-swift3-objc-inference-minimal\\\n"
    stream <<< "         -warnings-as-errors -Xcc -Xlinker\"\n"
    stream <<< "    COMPREPLY+=( $(compgen -W \"$args\" -- $cur))\n"
    stream <<< "    _filedir\n"
    stream <<< "}\n"
    
    stream <<< "complete -F _swift swift\n"
    
    stream.flush()
}


