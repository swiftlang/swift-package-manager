/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public func parse<Mode: ModeArgument, Flag: Argument>(arguments: [String]) throws -> (Mode?, [Flag]) {

    var mode: Mode!
    var it = arguments.makeIterator()

    var kept = [String]()
    while let arg = it.next() {
        var popped = false
        let (arg, value) = split(arg)

        if let mkmode = try Mode(argument: arg, pop: { popped = true; return value ?? it.next() }) {
            guard mode == nil || mode == mkmode else { throw Error.MultipleModesSpecified([mode, mkmode].map{"\($0)"})}
            mode = mkmode
        } else {
            kept.append(arg)
        }

        if value != nil && !popped {
            throw Error.InvalidUsage("\(arg) does not take an associated value",.Suggest)
        }
    }

    var flags = [Flag]()
    it = kept.makeIterator()
    while let arg = it.next() {
        var popped = false
        let (arg, value) = split(arg)

        if let flag = try Flag(argument: arg, pop: { popped = true; return value ?? it.next() }) {
            flags.append(flag)
        } else {
            throw Error.InvalidUsage("unknown argument: \(arg)", .Suggest)
        }

        if value != nil && !popped {
            throw Error.InvalidUsage("\(arg) does not take an associated value",.Suggest)
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
