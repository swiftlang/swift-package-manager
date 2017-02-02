/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import struct PackageModel.Manifest

public enum Error: Swift.Error {
    case noModules
    case onlyCModule(name: String)
    case incompatibleToolsVersions(module: String, required: [Int], current: Int)
}

extension Error: FixableError {
    public var error: String {
        switch self {
        case .noModules:
            return "no modules found"
        case .onlyCModule(let name):
            return "only system module package \(name) found"
        case .incompatibleToolsVersions(let module, let required, let current):
            let stream = BufferedOutputByteStream()
            if required.isEmpty {
                stream <<< "Target \(module)'s sources are not compatible with any compiler version."
                stream <<< " Either set a compatible compiler version or keep it nil to use the default version."
            } else {
                let requiredVersions = required.map{String($0)}.joined(separator: ", ")
                stream <<< "Target \(module)'s sources are compatible with compiler version(s): \(requiredVersions)."
                stream <<< " Current tools major version is \(current)"
            }
            return stream.bytes.asString!
        }
    }

    public var fix: String? {
        switch self {
            case .noModules:
                return "define a module inside \(Manifest.filename)"
            case .onlyCModule:
                return "to use this system module package, include it in another project"
            case .incompatibleToolsVersions:
                return nil
        }
    }
}
