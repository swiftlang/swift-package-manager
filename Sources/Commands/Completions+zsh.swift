//
//  zsh_template.swift
//  SwiftPM
//
//  Created by Bouke Haarsma on 29/09/2016.
//
//

import Foundation
import Basic
import Utility

func zsh_template(on stream: OutputByteStream) {
    stream <<< "#compdef swift\n"
    stream <<< "local context state state_descr line\n"
    stream <<< "typeset -A opt_args\n"
    stream <<< "\n"
    stream <<< "_swift() {\n"
    stream <<< "    declare -a shared_options\n"
    stream <<< "    shared_options=(\n"
    stream <<< "        '(-C --chdir)'{-C,--chdir}\"[Change working directory before any other operation]: :_files\"\n"
    stream <<< "        \"--color[Specify color mode (auto|always|never)]: :{_values \"mode\" auto always never}\"\n"
    stream <<< "        '(-v --verbose)'{-v,--verbose}'[Increase verbosity of informational output]'\n"
    stream <<< "        \"-Xcc[Pass flag through to all C compiler invocations]: : \"\n"
    stream <<< "        \"-Xlinker[Pass flag through to all linker invocations]: : \"\n"
    stream <<< "        \"-Xswiftc[Pass flag through to all Swift compiler invocations]: : \"\n"
    stream <<< "    )\n"
    stream <<< "\n"
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
    
    stream <<< "_swift_compiler() {\n"
    stream <<< "    declare -a build_options\n"
    stream <<< "    build_options=(\n"
    stream <<< "        '-assert-config[Specify the assert_configuration replacement.]: :{_values \"\" Debug Release Unchecked DisableReplacement}'\n"
    stream <<< "        '-D[Marks a conditional compilation flag as true]: : '\n"
    stream <<< "        '-framework[Specifies a framework which should be linked against]: : '\n"
    stream <<< "        '-F[Add directory to framework search path]: :_files'\n"
    stream <<< "        '-gdwarf-types[Emit full DWARF type info.]'\n"
    stream <<< "        '-gline-tables-only[Emit minimal debug info for backtraces only]'\n"
    stream <<< "        \"-gnone[Don't emit debug info]\"\n"
    stream <<< "        '-g[Emit debug info. This is the preferred setting for debugging with LLDB.]'\n"
    stream <<< "        '-help[Display available options]'\n"
    stream <<< "        '-index-store-path[Store indexing data to <path>]: :_files'\n"
    stream <<< "        '-I[Add directory to the import search path]: :_files'\n"
    stream <<< "        '-j[Number of commands to execute in parallel]: : '\n"
    stream <<< "        '-L[Add directory to library link search path]: :_files'\n"
    stream <<< "        '-l-[Specifies a library which should be linked against]: : '\n"
    stream <<< "        '-module-cache-path[Specifies the Clang module cache path]: :_files'\n"
    stream <<< "        '-module-link-name[Library to link against when using this module]: : '\n"
    stream <<< "        '-module-name[Name of the module to build]: : '\n"
    stream <<< "        \"-nostdimport[Don't search the standard library import path for modules]\"\n"
    stream <<< "        '-num-threads[Enable multi-threading and specify number of threads]: : '\n"
    stream <<< "        '-Onone[Compile without any optimization]'\n"
    stream <<< "        '-Ounchecked[Compile with optimizations and remove runtime safety checks]'\n"
    stream <<< "        '-O[Compile with optimizations]'\n"
    stream <<< "        '-sdk[Compile against <sdk>]: : '\n"
    stream <<< "        '-static-stdlib[Statically link the Swift standard library]'\n"
    stream <<< "        '-suppress-warnings[Suppress all warnings]'\n"
    stream <<< "        '-target-cpu[Generate code for a particular CPU variant]: : '\n"
    stream <<< "        '-target[Generate code for the given target]: : '\n"
    stream <<< "        '-use-ld=-[Specifies the linker to be used]'\n"
    stream <<< "        '-version[Print version information and exit]'\n"
    stream <<< "        '-v[Show commands to run and use verbose output]'\n"
    stream <<< "        '-warnings-as-errors[Treat warnings as errors]'\n"
    stream <<< "        '-Xcc[Pass <arg> to the C/C++/Objective-C compiler]: : '\n"
    stream <<< "        '-Xlinker[Specifies an option which should be passed to the linker]: : '\n"
    stream <<< "        '*:inputs:_files'\n"
    stream <<< "    )\n"
    stream <<< "    _arguments $build_options\n"
    stream <<< "}\n"
    stream <<< "\n"
    
    stream <<< "_swift\n"
    
    stream.flush()
}


