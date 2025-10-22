//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Subprocess
import TSCBasic

#if canImport(System)
import System
#else
import SystemPackage
#endif

extension Subprocess.Environment {
    public init(_ env: Basics.Environment) {
        var newEnv: [Subprocess.Environment.Key: String] = [:]
        for (key, value) in env {
            newEnv[.init(rawValue: key.rawValue)!] = value
        }
        self = Subprocess.Environment.custom(newEnv)
    }
}

extension Subprocess.Configuration {
    public init(commandLine: [String], environment: Subprocess.Environment) throws {
        guard let arg0 = commandLine.first else {
            throw StringError("command line was unexpectedly empty")
        }
        self.init(.path(FilePath(arg0)), arguments: .init(Array(commandLine.dropFirst())), environment: environment)
    }
}
