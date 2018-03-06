/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func SPMLibc.getcwd
import func SPMLibc.free
import func SPMLibc.exit
import func SPMLibc.fputs
import var SPMLibc.PATH_MAX
import var SPMLibc.stderr
import var SPMLibc.errno

/**
 - Returns: The absolute pathname of the current working directory.
 - Note: If the current directory does not exist, aborts program,
   to deal with this you should `opendir(getcwd())` as soon as your
   program starts and then not `chdir()`, `chdir` is an anti-pattern
   in tooling anyway.
 - Warning: As a result of the above note use of POSIX demands that
   the working directory not change during execution. This requires
   you to have control over the purity of your dependencies.
*/
public func getcwd() -> String {

    func error() -> Never {
        fputs("error: no current directory\n", SPMLibc.stderr)
        SPMLibc.exit(2)
    }

    let cwd = SPMLibc.getcwd(nil, Int(PATH_MAX))
    if cwd == nil { error() }
    defer { free(cwd) }
    guard let path = String(validatingUTF8: cwd!) else { error() }
    return path
}
