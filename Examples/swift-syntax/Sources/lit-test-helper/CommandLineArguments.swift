//===----- CommandLineArguments.swift - Command line argument parser ------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//


struct CommandLineArguments {
  struct MissingArgumentError: Error, CustomStringConvertible {
    let argName: String

    var description: String {
      return "Missing required argument: \(argName)"
    }
  }
  struct UnkeyedArgumentError: Error, CustomStringConvertible {
    let argName: String

    var description: String {
      return "Unexpectedly found command line argument \(argName) without a key"
    }
  }
  struct InvalidArgumentValueError: Error, CustomStringConvertible {
    let argName: String
    let value: String

    var description: String {
      return "\(value) is not a valid value for \(argName)"
    }
  }

  private let args: [String: String]

  static func parse<T: Sequence>(_ args: T) throws -> CommandLineArguments
    where T.Element == String {
      var parsedArgs: [String: String] = [:]
      var currentKey: String? = nil
      for arg in args {
        if arg.hasPrefix("-") {
          // Parse a new key
          if let currentKey = currentKey {
            // The last key didn't have a value. Just add it with an empty string as
            // the value to the parsed args
            parsedArgs[currentKey] = ""
          }
          currentKey = arg
        } else {
          if let currentKey = currentKey {
            parsedArgs[currentKey] = arg
          } else {
            throw UnkeyedArgumentError(argName: arg)
          }
          currentKey = nil
        }
      }
      if let currentKey = currentKey {
        // The last key didn't have a value. Just add it with an empty string as
        // the value to the parsed args
        parsedArgs[currentKey] = ""
      }
      return CommandLineArguments(args: parsedArgs)
  }

  subscript(key: String) -> String? {
    return args[key]
  }

  func getRequired(_ key: String) throws -> String {
    if let value = args[key] {
      return value
    } else {
      throw MissingArgumentError(argName: key)
    }
  }

  func has(_ key: String) -> Bool {
    return args[key] != nil
  }
}
