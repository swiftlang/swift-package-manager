/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 This file provides diagnostics that a user can inspect to infer common
 build troubles or for other troubleshooting purposes.
*/

import func POSIX.getenv
import func Utility.popen
import func Utility.which

func doctor() {
    print("LD:", getenv("LD") ?? "nil")
    print("which ld:", which("ld"))
}
