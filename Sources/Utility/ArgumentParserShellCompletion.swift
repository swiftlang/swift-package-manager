/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Basic

fileprivate let removeDefaultRegex = try! NSRegularExpression(pattern: "\\[default: .+?\\]", options: [])

extension ArgumentParser {

    /// Generates part of a completion script for the given shell.
    ///
    /// These aren't complete scripts, as some setup code is required. See
    /// `Utilities/bash/completions` and `Utilities/zsh/_swift` for example
    /// usage.
    public func generateCompletionScript(for shell: Shell, on stream: OutputByteStream) {
        guard let commandName = commandName else { abort() }
        let name = "_\(commandName.replacingOccurrences(of: " ", with: "_"))"

        switch shell {
        case .bash:
            // Information about how to include this function in a completion script.
            stream <<< "# Generates completions for \(commandName)\n"
            stream <<< "#\n"
            stream <<< "# Parameters\n"
            stream <<< "# - the start position of this parser; set to 1 if unknown\n"
            stream <<< "function \(name)\n"
            stream <<< "{\n"

            generateBashSwiftTool(name: name, on: stream)

        case .zsh:
            // Information about how to include this function in a completion script.
            stream <<< "# Generates completions for \(commandName)\n"
            stream <<< "#\n"
            stream <<< "# In the final compdef file, set the following file header:\n"
            stream <<< "#\n"
            stream <<< "#     #compdef \(name)\n"
            stream <<< "#     local context state state_descr line\n"
            stream <<< "#     typeset -A opt_args\n"

            generateZshSwiftTool(name: name, on: stream)
        }
        stream.flush()
    }

    // MARK: - BASH

    fileprivate func generateBashSwiftTool(name: String, on stream: OutputByteStream) {

        // Suggest positional arguments. Beware that this forces positional arguments
        // before options. For example [swift package pin <TAB>] expects a name as the
        // first argument. So no options (like --all) will be suggested. However after
        // the positional argument; [swift package pin MyPackage <TAB>] will list them
        // just fine.
        for (index, argument) in positionalArguments.enumerated() {
            stream <<< "    if [[ $COMP_CWORD == $(($1+\(index))) ]]; then\n"
            generateBashCompletion(argument, on: stream)
            stream <<< "    fi\n"
        }

        // Suggest subparsers in addition to other arguments.
        stream <<< "    if [[ $COMP_CWORD == $1 ]]; then\n"
        var completions = [String]()
        for (subName, _) in subparsers {
            completions.append(subName)
        }
        for option in optionArguments {
            completions.append(option.name)
            if let shortName = option.shortName {
                completions.append(shortName)
            }
        }
        stream <<< "        COMPREPLY=( $(compgen -W \"\(completions.joined(separator: " "))\" -- $cur) )\n"
        stream <<< "        return\n"
        stream <<< "    fi\n"

        // Suggest completions based on previous word.
        generateBashCasePrev(on: stream)

        // Forward completions to subparsers.
        stream <<< "    case ${COMP_WORDS[$1]} in\n"
        for (subName, _) in subparsers {
            stream <<< "        (\(subName))\n"
            stream <<< "            \(name)_\(subName) $(($1+1))\n"
            stream <<< "            return\n"
            stream <<< "        ;;\n"
        }
        stream <<< "    esac\n"

        // In all other cases (no positional / previous / subparser), suggest
        // this parsers completions.
        stream <<< "    COMPREPLY=( $(compgen -W \"\(completions.joined(separator: " "))\" -- $cur) )\n"
        stream <<< "}\n"
        stream <<< "\n"

        for (subName, subParser) in subparsers {
            subParser.generateBashSwiftTool(name: "\(name)_\(subName)", on: stream)
        }
    }

    fileprivate func generateBashCasePrev(on stream: OutputByteStream) {
        stream <<< "    case $prev in\n"
        for argument in optionArguments {
            let flags = [argument.name] + (argument.shortName.map({ [$0] }) ?? [])
            stream <<< "        (\(flags.joined(separator: "|")))\n"
            generateBashCompletion(argument, on: stream)
            stream <<< "        ;;\n"
        }
        stream <<< "    esac\n"
    }

    fileprivate func generateBashCompletion(_ argument: AnyArgument, on stream: OutputByteStream) {
        switch argument.kind.completion {
        case .none:
            // return; no value to complete
            stream <<< "            return\n"
        case .unspecified:
            break
        case .values(let values):
            let x = values.map({ $0.value }).joined(separator: " ")
            stream <<< "            COMPREPLY=( $(compgen -W \"\(x)\" -- $cur) )\n"
            stream <<< "            return\n"
        case .filename:
            stream <<< "            _filedir\n"
            stream <<< "            return\n"
        }
    }

    // MARK: - ZSH

    private func generateZshSwiftTool(name: String, on stream: OutputByteStream) {
        // Completions are provided by zsh's _arguments builtin.
        stream <<< "\(name)() {\n"
        stream <<< "    arguments=(\n"
        for argument in positionalArguments {
            stream <<< "        \""
            generateZshCompletion(argument, on: stream)
            stream <<< "\"\n"
        }
        for argument in optionArguments {
            generateZshArgument(argument, on: stream)
        }

        // Use a simple state-machine when dealing with sub parsers.
        if subparsers.count > 0 {
            stream <<< "        '(-): :->command'\n"
            stream <<< "        '(-)*:: :->arg'\n"
        }

        stream <<< "    )\n"
        stream <<< "    _arguments $arguments && return\n"

        // Handle the state set by the state machine.
        if subparsers.count > 0 {
            stream <<< "    case $state in\n"
            stream <<< "        (command)\n"
            stream <<< "            local modes\n"
            stream <<< "            modes=(\n"
            for (subName, subParser) in subparsers {
                stream <<< "                '\(subName):\(subParser.overview)'\n"
            }
            stream <<< "            )\n"
            stream <<< "            _describe \"mode\" modes\n"
            stream <<< "            ;;\n"
            stream <<< "        (arg)\n"
            stream <<< "            case ${words[1]} in\n"
            for (subName, _) in subparsers {
                stream <<< "                (\(subName))\n"
                stream <<< "                    \(name)_\(subName)\n"
                stream <<< "                    ;;\n"
            }
            stream <<< "            esac\n"
            stream <<< "            ;;\n"
            stream <<< "    esac\n"
        }
        stream <<< "}\n"
        stream <<< "\n"

        for (subName, subParser) in subparsers {
            subParser.generateZshSwiftTool(name: "\(name)_\(subName)", on: stream)
        }
    }

    /// Generates an option argument for `_arguments`, complete with description and completion values.
    fileprivate func generateZshArgument(_ argument: AnyArgument, on stream: OutputByteStream) {
        stream <<< "        \""
        switch argument.shortName {
        case .none: stream <<< "\(argument.name)"
        case let shortName?: stream <<< "(\(argument.name) \(shortName))\"{\(argument.name),\(shortName)}\""
        }

        let description = removeDefaultRegex
            .replace(in: argument.usage ?? "", with: "")
            .replacingOccurrences(of: "\"", with: "\\\"")
        stream <<< "[\(description)]"

        generateZshCompletion(argument, on: stream)
        stream <<< "\"\n"
    }

    /// Generates completion values, as part of an item for `_arguments`.
    fileprivate func generateZshCompletion(_ argument: AnyArgument, on stream: OutputByteStream) {
        let message = removeDefaultRegex
            .replace(in: argument.usage ?? " ", with: "")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch argument.kind.completion {
        case .none: stream <<< ":\(message): "
        case .unspecified: break
        case .filename: stream <<< ":\(message):_files"
        case let .values(values):
            stream <<< ": :{_values ''"
            for (value, description) in values {
                stream <<< " '\(value)[\(description)]'"
            }
            stream <<< "}"
        }
    }
}

fileprivate extension NSRegularExpression {
    func replace(`in` original: String, with replacement: String) -> String {
        return stringByReplacingMatches(
            in: original,
            options: [],
            range: NSRange(location: 0, length: original.characters.count),
            withTemplate: replacement)
    }
}
