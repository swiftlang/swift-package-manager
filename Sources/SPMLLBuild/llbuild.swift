/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if canImport(llbuildSwift)
@_exported import llbuildSwift
#elseif canImport(llbuild)
@_exported import llbuild
#else
// This should be a hard error in future.
#endif
