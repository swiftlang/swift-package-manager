/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(Linux)
import libc  // String.hasPrefix
#endif

public func parse<Mode, Flag where Mode: Argument, Mode: Equatable, Flag: Argument>(arguments: [String]) throws -> (Mode?, [Flag]) {

    var mode: Mode!
    var it = arguments.makeIterator()

    var kept = [String]()
    while let rawArg = it.next() {
        var popped = false
        let (arg, value) = split(rawArg)

        if let mkmode = try Mode(argument: arg, pop: { popped = true; return value ?? it.next() }) {
            guard mode == nil || mode == mkmode else {
                let modes = [mode, mkmode].map{"\($0)"}
                throw Error.MultipleModesSpecified(modes)
            }
            mode = mkmode

            if let value = value where !popped {
                throw Error.UnexpectedAssociatedValue(arg, value)
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

            guard !arg.hasPrefix("--") else { throw Error.UnknownArgument(arg) }
            guard arg != "-" else { throw Error.UnknownArgument(arg) }

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
                    throw Error.UnknownArgument(arg)
                }
                flags.append(flag)
            }
        }

        if let value = value where !popped {
            throw Error.UnexpectedAssociatedValue(arg, value)
        }
    }

    return (mode, flags)
}

private func split(_ arg: String) -> (String, String?) {
    let chars = arg.characters
    if let ii = chars.index(of: "=") {
        let flag = chars.prefix(upTo: ii)
        let value = chars.suffix(from: ii.advanced(by: 1))
        return (String(flag), String(value))
    } else {
        return (arg, nil)
    }
}
