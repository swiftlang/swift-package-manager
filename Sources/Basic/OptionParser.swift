/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(Linux)
    import Foundation  // String.hasPrefix
#endif

public enum OptionParserError: ErrorProtocol {
    case UnknownArgument(String)
    case MultipleModesSpecified([String])
    case ExpectedAssociatedValue(String)
    case UnexpectedAssociatedValue(String, String)
    case InvalidUsage(String)
}

extension OptionParserError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ExpectedAssociatedValue(let arg):
            return "expected associated value for argument: \(arg)"
        case .UnexpectedAssociatedValue(let arg, let value):
            return "unexpected associated value for argument: \(arg)=\(value)"
        case .MultipleModesSpecified(let modes):
            return "multiple modes specified: \(modes)"
        case .UnknownArgument(let cmd):
            return "unknown command: \(cmd)"
        case .InvalidUsage(let hint):
            return "invalid usage: \(hint)"
        }
    }
}

public protocol Argument {
    /**
     Attempt to convert the provided argument. If you need
     an associated value, call `pop()`, if there is no
     associated value we will throw. If the argument was
     passed `--foo=bar` and you don’t `pop` we also `throw`
    */
    init?(argument: String, pop: () -> String?) throws
}

public func parseOptions<Mode, Flag where Mode: Argument, Mode: Equatable, Flag: Argument>(arguments: [String]) throws -> (Mode?, [Flag]) {

    var mode: Mode!
    var it = arguments.makeIterator()

    var kept = [String]()
    while let rawArg = it.next() {
        var popped = false
        let (arg, value) = split(rawArg)

        if let mkmode = try Mode(argument: arg, pop: { popped = true; return value ?? it.next() }) {
            guard mode == nil || mode == mkmode else {
                let modes = [mode!, mkmode].map{"\($0)"}
                throw OptionParserError.MultipleModesSpecified(modes)
            }
            mode = mkmode

            if let value = value where !popped {
                throw OptionParserError.UnexpectedAssociatedValue(arg, value)
            }
        } else {
            kept.append(rawArg)
        }

    }

    var flags = [Flag]()
    it = kept.makeIterator()
    while let arg = it.next() {
        var popped = false
        let (arg, value) = split(arg)

        if let flag = try Flag(argument: arg, pop: { popped = true; return value ?? it.next() }) {
            flags.append(flag)
        } else if arg.hasPrefix("-") {

            // attempt to split eg. `-xyz` to `-x -y -z`

            guard !arg.hasPrefix("--") else { throw OptionParserError.UnknownArgument(arg) }
            guard arg != "-" else { throw OptionParserError.UnknownArgument(arg) }

            var characters = arg.characters.dropFirst()

            func pop() -> String? {
                if characters.isEmpty {
                    return nil
                } else {
                    // thus we support eg. `-mwip` as `-m=wip`
                    let str = String(characters)
                    characters.removeAll()
                    return str
                }
            }

            while !characters.isEmpty {
                let c = characters.removeFirst()
                guard let flag = try Flag(argument: "-\(c)", pop: pop) else {
                    throw OptionParserError.UnknownArgument(arg)
                }
                flags.append(flag)
            }
        } else {
          throw OptionParserError.UnknownArgument(arg)
        }

        if let value = value where !popped {
            throw OptionParserError.UnexpectedAssociatedValue(arg, value)
        }
    }

    return (mode, flags)
}

private func split(_ arg: String) -> (String, String?) {
    let chars = arg.characters
    if let ii = chars.index(of: "=") {
        let flag = chars.prefix(upTo: ii)
        let value = chars.suffix(from: chars.index(after: ii))
        return (String(flag), String(value))
    } else {
        return (arg, nil)
    }
}
